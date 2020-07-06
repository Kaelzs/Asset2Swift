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

    private func imageContent(for imageAssets: String, in fileManager: FileManager) throws -> [String] {
        let suffix = ".imageset"

        return try fileManager.subpathsOfDirectory(atPath: imageAssets).filter {
            $0.hasSuffix(suffix)
        }.map { path -> String in
            return String(path.replacingOccurrences(of: "/", with: "_").dropLast(suffix.count))
        }.map { name in
            return """
            static var \(name): UIImage { return UIImage(named: "\(name)")! }
            """
        }
    }

    private func colorDescription(for colorContents: ColorContents) -> String {
        if colorContents.colors.count == 0 {
            return "No descriptions"
        } else if colorContents.colors.count == 1 {
            return colorContents.colors.first!.color.rgbComponents.hexDescriptions
        } else {
            return colorContents.colors.map { colorGroup -> String in
                return colorGroup.identifierDescriptions + ": " + colorGroup.color.rgbComponents.hexDescriptions
            }.joined(separator: ", ")
        }
    }

    private func colorContent(for colorAssets: String, in fileManager: FileManager) throws -> [String] {
        let suffix = ".colorset"
        let fileSuffix = ".json"

        let jsonDecoder = JSONDecoder()

        return try fileManager.subpathsOfDirectory(atPath: colorAssets).filter {
            $0.contains(suffix) && $0.hasSuffix(fileSuffix)
        }.compactMap { path in
            guard let fileData = fileManager.contents(atPath: colorAssets.hasSuffix("/") ? (colorAssets + path) : (colorAssets + "/" + path)) else {
                print("cannot find file")
                return nil
            }
            do {
                let colorContents = try jsonDecoder.decode(ColorContents.self, from: fileData)
                let name = path.split(separator: "/").dropLast().joined(separator: "_").dropLast(suffix.count)

                return """
                static var \(name): UIColor { return UIColor(named: "\(name)")! } // \(colorDescription(for: colorContents))
                """
            } catch {
                print(error)
                return nil
            }
        }
    }

    private func replace(placeholderRange: Range<String.Index>, with stringGroup: [String], in templateString: inout String) {
        let imageString: String
        let replacedRange: Range<String.Index>
        if let newLineRange = templateString.rangeOfCharacter(from: .newlines, options: .backwards, range: templateString.startIndex ..< placeholderRange.lowerBound) {
            let prefix = String(templateString[newLineRange.upperBound ..< placeholderRange.lowerBound])
            imageString = stringGroup.map {
                prefix + $0
            }.joined(separator: "\n")
            replacedRange = newLineRange.upperBound ..< placeholderRange.upperBound
        } else {
            imageString = stringGroup.joined(separator: "\n")
            replacedRange = placeholderRange
        }

        templateString.replaceSubrange(replacedRange, with: imageString)
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

        if let imageTemplateRange = templateString.range(of: "$IMAGES") {
            let imageContents = try imageAssets.flatMap { try imageContent(for: $0, in: manager) } ?? []
            replace(placeholderRange: imageTemplateRange, with: imageContents, in: &templateString)
        }

        if let colorTemplateRange = templateString.range(of: "$COLORS") {
            let colorContents = try colorAssets.flatMap { try colorContent(for: $0, in: manager) } ?? []
            replace(placeholderRange: colorTemplateRange, with: colorContents, in: &templateString)
        }

        try templateString.data(using: .utf8)?.write(to: outputUrl)

        print("write code to \(output) successful!")
    }
}

GenerateCommand.main()
