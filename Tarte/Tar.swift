//
//  Tar.swift
//  Tarte
//
//  Created by Antoine Marandon on 17/07/2020.
//  Copyright © 2020 ntnmrndn. All rights reserved.
//

import Foundation

enum Tar {
    static let blockSize = 512
    struct Header {
        static let size = Tar.blockSize
        static let fileNameOffset = 0
        static let fileNameLenght = 100
        static let fileSizeOffset = 124
        static let fileSizeLenght = 12
        static let checkSumLenght = 8
        static let checkSumOffset = 148
        static let magicOffset = 257
        static let magic = "ustar"
        static let fileTypeOffset = 156
        static let linkNameOffset = 157
        static let linkNameLenght = 100

        enum Error: Swift.Error {
            case headerParsingError
            case badMagic
            case memoryAllocationError
        }
        ///XXX some types are not supported
        enum TypeFlag {
            enum Error: Swift.Error {
                case unkownType
            }
            case file
            case hardLink(linkName: String)
            case symLink(linkName: String)
            case directory

            init(_ value: UInt8, linkNameBuffer: UnsafeMutablePointer<UInt8>) throws {
                switch value {
                case 0, Character("0").asciiValue:
                    self = .file
                case Character("1").asciiValue:
                    self = try .hardLink(linkName: Header.safeString(linkNameBuffer, lenght: Header.linkNameLenght))
                case Character("2").asciiValue:
                    self = try .symLink(linkName: Header.safeString(linkNameBuffer, lenght: Header.linkNameLenght))
                case Character("5").asciiValue:
                    self = .directory
                default:
                    throw Error.unkownType
                }
            }
        }
        //        char name[100];               /*   0 */
        //        char mode[8];                 /* 100 */
        //        char uid[8];                  /* 108 */
        //        char gid[8];                  /* 116 */
        //        char size[12];                /* 124 */
        //        char mtime[12];               /* 136 */
        //        char chksum[8];               /* 148 */
        //        char typeflag;                /* 156 */
        //        char linkname[100];           /* 157 */
        //        char magic[6];                /* 257 */
        //        char version[2];              /* 263 */
        //        char uname[32];               /* 265 */
        //        char gname[32];               /* 297 */
        //        char devmajor[8];             /* 329 */
        //        char devminor[8];             /* 337 */
        //        char prefix[155];             /* 345 */
        let fileName: String
        let fileSize: Int
        let fileType: TypeFlag
        /// As much as I hate copying data, we can't trust strings to be nil terminated, so either make a copy or make available a strntol implementation
        private static func safeStrtol(_ pointer: UnsafeMutablePointer<UInt8>, lenght: Int, base: Int32) throws -> Int {
            let string = pointer.withMemoryRebound(to: Int8.self, capacity: lenght) {
                strndup($0, lenght)
            }
            guard string != nil else {
                throw Error.memoryAllocationError
            }
            defer { free(string) }
            return strtol(string, nil, base)
        }

        private static func safeString(_ buffer: UnsafeMutablePointer<UInt8>, lenght: Int) throws -> String {
            if let string = String(data: Data(bytes: buffer, count: lenght), encoding: .utf8) {
                return string
            } else {
                throw Error.headerParsingError
            }
        }

        init(buffer: UnsafeMutablePointer<UInt8>) throws {
            for (index, character) in Self.magic.enumerated() {
                guard buffer[Self.magicOffset + index] == character.asciiValue else {
                    throw Error.badMagic
                }
            }
            guard buffer[Self.magicOffset + Self.magic.count] == 0 else {
                throw Error.badMagic
            }
            //XXX check checksum
            //XXX implement all header fields
            self.fileName = try Self.safeString(buffer.advanced(by: Self.fileNameOffset), lenght: Self.fileNameLenght)
            self.fileSize = try Self.safeStrtol(buffer.advanced(by: Self.fileSizeOffset), lenght: Self.fileSizeLenght, base: 8)
            self.fileType = try .init(buffer[Self.fileTypeOffset], linkNameBuffer: buffer.advanced(by: Self.linkNameOffset))
        }

        var padding: Int {
            Tar.blockSize - fileSize % Tar.blockSize
        }
    }
}