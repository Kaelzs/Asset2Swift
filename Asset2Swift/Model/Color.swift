//
//  Color.swift
//  Asset2Swift
//
//  Created by Kael Yang on 6/7/2020.
//  Copyright © 2020 Kael Yang. All rights reserved.
//

import Foundation

struct ColorContents: Codable {
    struct Info: Codable {
        let author: String
        let version: Int
    }

    struct ColorGroup: Codable {
        struct Color: Codable {
            struct RGBComponents: Codable {
                let alpha: String
                let blue: String
                let green: String
                let red: String

                var alphaValue: Double {
                    return Double(alpha) ?? 0
                }
                var blueValue: Double {
                    return Double(blue) ?? 0
                }
                var greenValue: Double {
                    return Double(green) ?? 0
                }
                var redValue: Double {
                    return Double(red) ?? 0
                }

                var hexDescriptions: String {
                    let rgbHex = String(format: "#%02X%02X%02X", Int(round(redValue * 255)), Int(round(greenValue * 255)), Int(round(blueValue * 255)))
                    return alphaValue == 1.0 ? rgbHex : (rgbHex + String(format: "%02X", Int(round(alphaValue * 255))))
                }
            }

            let colorSpace: String
            let rgbComponents: RGBComponents

            enum CodingKeys: String, CodingKey {
                case colorSpace = "color-space"
                case rgbComponents = "components"
            }
        }

        struct Appearance: Codable {
            let appearance: String
            let value: String
        }

        let appearances: [Appearance]?
        let color: Color
        let idiom: String

        var identifierDescriptions: String {
            return (idiom == "universal" ? "" : (idiom + "-")) + (appearances?.map { $0.value }.joined(separator: ", ") ?? "any")
        }
    }

    let colors: [ColorGroup]
    let info: Info
}
