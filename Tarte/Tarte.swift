//
//  Tarte.swift
//  Tarte
//
//  Created by Antoine Marandon on 16/07/2020.
//  Copyright © 2020 ntnmrndn. All rights reserved.
//

import Foundation

#if os(Linux)
import SwiftGlibc
#else
import Darwin
#endif

fileprivate extension InputStream {
    var isFinished: Bool {
        if self.hasBytesAvailable {
            return false
        }
        switch self.streamStatus {
        case .notOpen:
            return true
        case .opening:
            return false
        case .open:
            return false
        case .reading:
            return false
        case .writing:
            return false
        case .atEnd:
            return true
        case .closed:
            return false
        case .error:
            return true
        @unknown default:
            return true
        }
    }
}

public class Tarte: NSObject, StreamDelegate {
    public enum Error: Swift.Error {
        case couldNotConvertInputURLToStream
        case encounteredStreamError(Swift.Error?)
        case couldNotOpenOutputStream
        case errorWritingToStream(Swift.Error?)
        case unsupportedType
        case badFooter
        case fileTooSmall
    }
    private enum State {
        case readingFile(header: Tar.Header, stream: OutputStream, remainingSize: Int)
        case readingHeader(remainingSize: Int)
        case readingPadding(remainingSize: Int)
        case readingLocalExtendedHeader(header: Tar.Header, remainingSize: Int)
        case finished
    }
    private var state: State = .readingHeader(remainingSize: Tar.Header.size)
    private let stream: InputStream
    private let readBufferSize = 4096 //XXX test different buffer sizes. Maybe refactor to use the stream.buffer if available

    private let destination: URL
    private var resultBlock:((Result<Void, Swift.Error>) -> Void)?
    private var streamSemaphore = DispatchSemaphore(value: 0)
    private var foundTarHeader = false
    private var localExtendedHeader: Tar.ExtendedLocalHeader?
    public init(stream: InputStream, destination: URL, resultBlock: @escaping (Result<Void, Swift.Error>) -> Void) {
        self.stream = stream
        self.destination = destination
        self.resultBlock = resultBlock
    }

    private static func isFooter(buffer: UnsafeMutablePointer<UInt8>) -> Bool {
        for i in (0..<Tar.Header.size) {
            if buffer[i] != 0 {
                return false
            }
        }
        return true
    }

    /// Consume attempt to read the buffer, and return the number of bit read.
    /// If this number if smaller than the readBufferAvailableLenght, it means we cannot make use of the data, and the buffer should be filled with more data before attempting to consume() again.
    private func consume(buffer: UnsafeMutablePointer<UInt8>, lenght: Int) throws -> Int {
        guard lenght > 0 else { return 0 }
        switch state {
        case .readingHeader(remainingSize: let remainingSize):
            if lenght < remainingSize {
                return 0 // Ask for a full header to be written in the buffer.
            }
            if Self.isFooter(buffer: buffer) {
                self.state = .finished // XXX we should check for a double footer.
                return lenght
            }
            let header = try Tar.Header(buffer: buffer)
            self.foundTarHeader = true
            switch header.fileType {
            case .directory:
                let path = destination.appendingPathComponent(header.fileName, isDirectory: true)
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)
            case .file:
                let path: URL = {
                    if let path = localExtendedHeader?.path {
                        return destination.appendingPathComponent(path, isDirectory: false)
                    }
                    return destination.appendingPathComponent(header.prefix, isDirectory: true)
                        .appendingPathComponent(header.fileName, isDirectory: false)
                }()
                try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                FileManager.default.createFile(atPath: path.path, contents: nil, attributes: nil)
                if header.fileSize > 0 {
                    guard let outputStream = OutputStream(url: path, append: false) else {
                        throw Error.couldNotOpenOutputStream
                    }
                    outputStream.open()
                    outputStream.delegate = self
                    self.stream.schedule(in: .main, forMode: .default)
                    self.state = .readingFile(header: header, stream: outputStream, remainingSize: header.fileSize)
                }
            case .extendedLocalHeader:
                self.state = .readingLocalExtendedHeader(header: header, remainingSize: Tar.ExtendedLocalHeader.size)
            default:
                throw Error.unsupportedType
            }
            self.localExtendedHeader = nil
            let nextConsumedBytes = try consume(buffer: buffer.advanced(by: Tar.Header.size), lenght: lenght - Tar.Header.size)
            return Tar.Header.size + nextConsumedBytes
        case .readingFile(header: let header, stream: let stream, remainingSize: let remainingSize):
            guard stream.hasSpaceAvailable else {
                return 0
            }
            let writtenSize = stream.write(buffer, maxLength: min(remainingSize, lenght))
            if writtenSize < 0 {
                throw Error.encounteredStreamError(stream.streamError)
            } else if remainingSize == writtenSize {
                stream.close()
                self.state = .readingPadding(remainingSize: header.padding)
                let nextConsumedBytes = try self.consume(buffer: buffer.advanced(by: writtenSize), lenght: lenght - writtenSize)
                return writtenSize + nextConsumedBytes
            } else if lenght - writtenSize > 0 {
                self.state = .readingFile(header: header, stream: stream, remainingSize: remainingSize - writtenSize)
                return writtenSize
            } else {
                self.state = .readingFile(header: header, stream: stream, remainingSize: remainingSize - writtenSize)
                return writtenSize //We ate consumed all data, ask for more.
            }
        case .finished:
            return lenght
        case .readingPadding(remainingSize: let remainingSize):
            let paddingBytesConsumed = min(remainingSize, lenght)
            if paddingBytesConsumed == remainingSize {
                state = .readingHeader(remainingSize: Tar.Header.size)
            }
            let nextConsumedBytes = try consume(buffer: buffer.advanced(by: paddingBytesConsumed), lenght: lenght - paddingBytesConsumed)
            return paddingBytesConsumed + nextConsumedBytes
        case .readingLocalExtendedHeader(header: _, remainingSize:  let remainingSize):
            if lenght < remainingSize {
                return 0 // Ask for a full header to be written in the buffer.
            }
            self.localExtendedHeader = try Tar.ExtendedLocalHeader(buffer: buffer)
            state = .readingHeader(remainingSize: Tar.Header.size)
            let nextConsumedBytes = try consume(buffer: buffer.advanced(by: Tar.Header.size), lenght: lenght - Tar.Header.size)
            return Tar.ExtendedLocalHeader.size + nextConsumedBytes
        }
    }

    private var outputStreamReady: Bool {
        switch self.state {
        case .readingFile(header: let header, stream: let stream, remainingSize: let remainingSize):
            return remainingSize == 0 || stream.hasSpaceAvailable
        case .finished:
            return true
        case .readingHeader(remainingSize: _):
            return true
        case .readingLocalExtendedHeader(header: _, remainingSize: _):
            return true
        case .readingPadding(remainingSize: _):
            return true
        }
    }


    private func untar() {
        precondition(!Thread.isMainThread)
        stream.delegate = self
        stream.open()
        defer { stream.close() }
        self.stream.schedule(in: .main, forMode: .default)
        let readBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity:
            self.readBufferSize)
        defer { readBuffer.deallocate() }
        var offset = 0
        do {
            while !stream.isFinished, resultBlock != nil {
                if stream.hasBytesAvailable, self.outputStreamReady {
                    let sizeAvailable = offset < readBufferSize ?
                        stream.read(readBuffer.advanced(by: offset), maxLength: readBufferSize - offset) : 0 /// if buffer is full, skip and consume. Assume we stalled because of an output buffer
                    let consumedSize = try consume(buffer: readBuffer, lenght: sizeAvailable + offset)
                    switch consumedSize {
                    case 0:
                        offset += sizeAvailable
                    case 0..<sizeAvailable:
                        /// To avoid cases where a header is a the end of our buffer, and no available space would be left to finish reading it, remove read data from the buffer
                        let remainingData = sizeAvailable + offset - consumedSize
                        memmove(readBuffer, readBuffer.advanced(by: consumedSize), remainingData)
                        offset = remainingData
                    case sizeAvailable:
                        offset = 0
                    default:
                        fatalError("Should not happen")
                    }
                } else {
                    streamSemaphore.wait()
                }
            }
            if foundTarHeader == false {
                throw Error.fileTooSmall
            }
        } catch {
            resultBlock?(.failure(error))
            resultBlock = nil
        }
        resultBlock?(. success(()))
        resultBlock = nil
    }

    @objc dynamic public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .endEncountered:
        return // Do something ?
        case .errorOccurred:
            resultBlock?(
                .failure(Error.encounteredStreamError(stream.streamError))
            )
            resultBlock = nil
        case .hasBytesAvailable:
            streamSemaphore.signal()
            return
        case .hasSpaceAvailable,
             .openCompleted:
            streamSemaphore.signal()
        default:
            assertionFailure("Unknow stream event occured") //XXX
            return
        }
    }

    public static func unTar(_ url: URL, to: URL, result: @escaping (Result<Void, Swift.Error>) -> Void) throws {
        guard let inputStream = InputStream(url: url) else {
            throw Error.couldNotConvertInputURLToStream
        }
        unTar(inputStream, to: to, result: result)
    }

    public static func unTar(_ stream: InputStream, to: URL, result: @escaping (Result<Void, Swift.Error>) -> Void) {
        let tarte = Tarte(stream: stream, destination: to, resultBlock: result)
        tarte.untar()
    }
}
