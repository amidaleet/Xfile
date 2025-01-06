#!/usr/bin/env swift

import Foundation

@discardableResult
func shell(_ command: String) throws -> String {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.standardInput = nil

    try task.run()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)!
}

let output = try shell("git rev-list --count HEAD")
let number = output.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
print(number)
