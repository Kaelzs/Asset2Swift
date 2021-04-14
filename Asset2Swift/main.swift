//
//  main.swift
//  Asset2Swift
//
//  Created by Kael Yang on 3/7/2020.
//  Copyright © 2020 Kael Yang. All rights reserved.
//

import ArgumentParser
import Foundation

struct GenerateCommand: ParsableCommand {
    enum Error: Swift.Error {
        case fileNoteAvailable(String)
    }

    static var configuration: CommandConfiguration = CommandConfiguration(commandName: "generate", abstract: "generate the swift image definations from asset folder")

    @Option(name: .shortAndLong, help: "the image asset folder")
    var imageAssets: String?

    @Option(name: .shortAndLong, help: "the color asset folder")
    var colorAssets: String?

    @Option(name: .shortAndLong, help: "the template of output file, the generator will replace the $IMAGES and $COLORS of the template")
    var template: String

    @Option(name: .shortAndLong, help: "the output swift file")
    var output: String

    private func split(values: [(String, String)]) -> [String] {
        return values.reduce(into: [String: [String]]()) { result, current in
            let (path, name) = current
            if var array = result[path] {
                let index = array.firstIndex(where: { $0 >= name }) ?? array.endIndex
                array.insert(name, at: index)
                result[path] = array
            } else {
                result[path] = [name]
            }
        }.sorted {
            $0.key < $1.key
        }.flatMap { key, values -> [String] in
            let keyDescription = key.isEmpty ? "file" : key
            return ["// Assets in \(keyDescription)"] + values + [""]
        }.dropLast()
    }

    private static let defaultImagePattern = "static var $IMAGENAME: UIImage { return UIImage(named: \"$IMAGENAME\")! }"
    private func imageContent(for imageAssets: String, in fileManager: FileManager, withPattern pattern: String = GenerateCommand.defaultImagePattern) throws -> [String] {
        let suffix = ".imageset"

        let result = try fileManager.subpathsOfDirectory(atPath: imageAssets).filter {
            $0.hasSuffix(suffix)
        }.map { path -> (String, String) in
            var splitted = path.split(separator: "/")
            let name = splitted.removeLast().dropLast(suffix.count)
            return (splitted.reduce("", { $0.isEmpty ? String($1) : $1.capitalized }), pattern.replacingOccurrences(of: "$IMAGENAME", with: name))
        }

        return split(values: result)
    }

    private func colorDescription(for colorContents: ColorContents) -> String? {
        if colorContents.colors.count == 0 {
            return nil
        } else if colorContents.colors.count == 1 {
            return colorContents.colors.first!.color.rgbComponents.hexDescriptions
        } else {
            return colorContents.colors.map { colorGroup -> String in
                return colorGroup.identifierDescriptions + ": " + colorGroup.color.rgbComponents.hexDescriptions
            }.joined(separator: ", ")
        }
    }

    private static let defaultColorPattern = "static var $COLORNAME: UIColor { return UIColor(named: \"$COLORNAME\")! }"
    private func colorContent(for colorAssetsPath: String, in fileManager: FileManager, withPattern pattern: String = GenerateCommand.defaultColorPattern) throws -> [String] {
        let suffix = ".colorset"
        let fileSuffix = ".json"

        let jsonDecoder = JSONDecoder()

        let result = try fileManager.subpathsOfDirectory(atPath: colorAssetsPath).filter {
            $0.contains(suffix) && $0.hasSuffix(fileSuffix)
        }.map { path -> (String, String, String) in
            var splitted = path.split(separator: "/")
            splitted.removeLast()
            let name = splitted.removeLast().dropLast(suffix.count)
            return (path, splitted.reduce("", { $0.isEmpty ? String($1) : $1.capitalized }), pattern.replacingOccurrences(of: "$COLORNAME", with: name))
        }.compactMap { path, folderDescription, description -> (String, String)? in
            guard let fileData = fileManager.contents(atPath: colorAssetsPath.hasSuffix("/") ? (colorAssetsPath + path) : (colorAssetsPath + "/" + path)),
                let colorContents = try? jsonDecoder.decode(ColorContents.self, from: fileData) else {
                return nil
            }
            return (folderDescription, description + (colorDescription(for: colorContents).flatMap { " // \($0)" } ?? ""))
        }

        return split(values: result)
    }

    private func replace(placeholderRange: Range<String.Index>, with stringGroup: [String], in templateString: inout String) {
        let imageString: String
        let replacedRange: Range<String.Index>
        if let newLineRange = templateString.rangeOfCharacter(from: .newlines, options: .backwards, range: templateString.startIndex ..< placeholderRange.lowerBound) {
            let prefix = String(templateString[newLineRange.upperBound ..< placeholderRange.lowerBound])
            imageString = stringGroup.map {
                if $0.isEmpty {
                    return $0
                }
                return prefix + $0
            }.joined(separator: "\n")
            replacedRange = newLineRange.upperBound ..< placeholderRange.upperBound
        } else {
            imageString = stringGroup.joined(separator: "\n")
            replacedRange = placeholderRange
        }

        templateString.replaceSubrange(replacedRange, with: imageString)
    }

    func getPatterParameters(inString string: String, withPlaceholder placeholder: String) -> (String, Range<String.Index>)? {
        if let imageNamePatternRange = string.range(of: placeholder) {
            let newLineStart = string[..<imageNamePatternRange.lowerBound].lastIndex(where: { $0.isNewline }) ?? string.startIndex
            let newLineEnd = string[imageNamePatternRange.upperBound...].firstIndex(where: { $0.isNewline }) ?? string.endIndex
            let codeStart = string[newLineStart..<newLineEnd].firstIndex(where: { !$0.isWhitespace })!
            let codeEnd = string.index(after: string[newLineStart..<newLineEnd].lastIndex(where: { !$0.isWhitespace })!)

            let pattern = String(string[codeStart..<codeEnd])

            return (pattern, codeStart..<codeEnd)
        }
        return nil
    }

    func run() throws {
        let manager = FileManager()

        guard var templateString = manager.contents(atPath: template).flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw Error.fileNoteAvailable(self.template)
        }

        let outputUrl = URL(fileURLWithPath: output)
        guard manager.fileExists(atPath: output) else {
            throw Error.fileNoteAvailable(output)
        }

        if let (pattern, imageNamePatternRange) = getPatterParameters(inString: templateString, withPlaceholder: "$IMAGENAME") {
            let imageContents = try imageAssets.flatMap { try imageContent(for: $0, in: manager, withPattern: pattern) } ?? []
            replace(placeholderRange: imageNamePatternRange, with: imageContents, in: &templateString)
        } else if let imageTemplateRange = templateString.range(of: "$IMAGES") {
            let imageContents = try imageAssets.flatMap { try imageContent(for: $0, in: manager) } ?? []
            replace(placeholderRange: imageTemplateRange, with: imageContents, in: &templateString)
        }

        if let (pattern, colorNamePatternRange) = getPatterParameters(inString: templateString, withPlaceholder: "$COLORNAME") {
            let colorContents = try colorAssets.flatMap { try colorContent(for: $0, in: manager, withPattern: pattern) } ?? []
            replace(placeholderRange: colorNamePatternRange, with: colorContents, in: &templateString)
        } else if let colorTemplateRange = templateString.range(of: "$COLORS") {
            let colorContents = try colorAssets.flatMap { try colorContent(for: $0, in: manager) } ?? []
            replace(placeholderRange: colorTemplateRange, with: colorContents, in: &templateString)
        }

        try templateString.data(using: .utf8)?.write(to: outputUrl)

        print("write code to \(output) successful!")
    }
}

GenerateCommand.main()
