import Foundation
import RoadStationCore
#if os(Windows)
import ucrt
#elseif canImport(Glibc)
import Glibc
#else
import Darwin
#endif

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(code)
}
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 3 || args.count == 5 else {
    fail("Usage: roadstation-validate alignment.xml cases.json output-prefix [--directions east-ccw|north-ccw|north-cw]")
}
do {
    var options = LandXMLParserOptions()
    if args.count == 5 {
        guard args[3] == "--directions" else { fail("Unknown option \(args[3])") }
        switch args[4] {
        case "east-ccw": options.directionConvention = .eastCounterclockwise
        case "north-ccw": options.directionConvention = .northCounterclockwise
        case "north-cw": options.directionConvention = .northClockwise
        default: fail("Unknown direction convention \(args[4])")
        }
    }
    let project = try LandXMLParser(options: options).parse(url: URL(fileURLWithPath: args[0]))
    for warning in project.warnings + project.alignments.flatMap(\.warnings) {
        FileHandle.standardError.write(Data(("Warning: " + warning + "\n").utf8))
    }
    let cases = try ValidationRunner.loadJSON(Data(contentsOf: URL(fileURLWithPath: args[1])))
    guard !cases.isEmpty else { fail("Validation case file is empty.") }
    let results = ValidationRunner.run(cases: cases, alignments: project.alignments)
    let output = URL(fileURLWithPath: args[2])
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try ValidationExporter.json(results).write(to: URL(fileURLWithPath: args[2] + ".json"), options: .atomic)
    try ValidationExporter.csv(results).write(to: URL(fileURLWithPath: args[2] + ".csv"), atomically: true, encoding: .utf8)
    let passed = results.filter(\.passed).count
    print("\(passed)/\(results.count) validation cases passed. Exported \(args[2]).json and .csv")
    for r in results where !r.passed { print("FAIL \(r.validationCase.id): \(r.error ?? "numerical difference exceeds tolerance")") }
    if passed != results.count { exit(1) }
} catch { fail(error.localizedDescription) }
