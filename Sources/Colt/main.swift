import Foundation
import ArgumentParser
import Network
import Progress
import INI

var slCode: String = ""
var tlCode: String = ""
var inputPath: String = ""
var inputPathIsDirectory = true
var tlOutputPath: String?
var currentSlIndex: Int = 0
var slStringsURLs: [URL] = []
var slStringsFileName: String = ""
var slStringsURL: URL?
var tlStringsURL: URL?
var slStringsDictionary: [String: String] = [:]
var slStringsURLS: [String: URL] = [:]
var tlStringsDictionary: [String: String] = [:]
var slStrings: [String: String] = [:]
var translationFailures: [String: String] = [:]
var progressBar: ProgressBar?
var translationRetryCount = 0
var translationRetryMax = 5

let localFileManager = FileManager()
var stringsFileHeader: String = ""

let dispatchGroup = DispatchGroup()

let sessionConfiguration = URLSessionConfiguration.default
let session = URLSession(configuration: sessionConfiguration)

// x-rapidapi-key will be supplied by the user
var systranHeaders = [
    "x-rapidapi-host": "systran-systran-platform-for-language-processing-v1.p.rapidapi.com",
    "x-rapidapi-key": ""
]

struct Translate: ParsableCommand {
    @Argument(help: "Language code of source file")
	var sl: String

    @Argument(help: "Language code of translation")
	var tl: String

    @Argument(help: "Path to a single file or directory to translate.")
    var path: String

    @Option(name: .shortAndLong, help: "Path to save output file(s).")
    var outputPath: String?

	func run() throws {
        slCode = sl
        tlCode = tl
        inputPath = path
        tlOutputPath = outputPath
        startColt()
	}
}

func startColt() {
    print("Colt Translating: \(slCode) to \(tlCode)")
    
    // Retreive rapidapi-key from .colt file in home directory
    var coltFilePath: URL
    if #available(OSX 10.12, *) {
        coltFilePath = FileManager.default.homeDirectoryForCurrentUser
    } else {
        coltFilePath = URL(fileURLWithPath: NSHomeDirectory())
    }
    coltFilePath.appendPathComponent(".colt")

    do {
        let coltFileContents = try String(contentsOf: coltFilePath)
        let parsedINI = try parseINI(string: coltFileContents)
        systranHeaders["x-rapidapi-key"] = parsedINI["keys"]?["rapidapi"]
    } catch {
        showError("RapidAPI key not found")
    }

    // Check for network if OS is above 10.14, otherwise let 'em through
    if #available(OSX 10.14, *) {
        let monitor = NWPathMonitor()
        dispatchGroup.enter()
        monitor.pathUpdateHandler = { path in
            if path.status != .satisfied {
                showError("Please check your network connection.")
            }
            dispatchGroup.leave()
        }
        let queue = DispatchQueue(label: "Monitor")
        monitor.start(queue: queue)
        dispatchGroup.wait()
        monitor.cancel()
    }

    //swiftlint:disable line_length
    stringsFileHeader = "/*\nThis file was translated using Colt on \(Date())\nhttps://github.com/mmwwwhahaha/colt\nSource language: \(slCode)\nTranslated to: \(tlCode)\n*/"

    // validate output path
    if let outputPath = tlOutputPath {
        if outputPath.directoryExists {
            tlOutputPath?.append(tlCode + "_" + slStringsFileName)
        } else if !outputPath.directoryExists && !outputPath.deletingLastPathComponent.directoryExists {
            showError("Please enter a valid output path")
        }
    }
    
    inputPathIsDirectory = inputPath.directoryExists
    inputPathIsDirectory ? findAllStringsFiles() : findSingleStringsFile()
}

func findSingleStringsFile() {
    if !inputPath.starts(with: "file://") {
        inputPath = "file://" + inputPath
    }
    if let url = URL(string: inputPath) {
        if url.lastPathComponent.lowercased().contains("coltignore") {
            showError("A file cannot be translated if it has 'coltIgnore' in its title")
        } else {
            slStringsURLs.append(url)
            parseSourceLanguageFile()
        }
    } else {
        showError("Source language file cannot be found.")
    }
}

func findAllStringsFiles() {
    let directoryEnumerator = localFileManager.enumerator(at: URL(fileURLWithPath: inputPath), includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

    while let fileURL = directoryEnumerator?.nextObject() as? URL, slStringsURL == nil || tlStringsURL == nil {
        if fileURL.lastPathComponent.lowercased().contains("coltignore") { continue }

        if fileURL.absoluteString.contains("\(slCode).lproj") && fileURL.lastPathComponent.contains(".strings") {
             slStringsURLs.append(fileURL)
        } else if fileURL.absoluteString.contains("\(tlCode).lproj") && fileURL.lastPathComponent.contains(".strings") {
             tlStringsURL = fileURL // currently not used. will be used when no longer overwriting files, post-MVP.
        }
     }

     if slStringsURLs.count == 0 {
         showError("Localization folder cannot be found, or all strings file are being ignored.")
         exit(EXIT_FAILURE)
     } else {
         parseSourceLanguageFile()
     }
}

func parseSourceLanguageFile() {
    slStringsURL = slStringsURLs[currentSlIndex]
    if let stringsURL = slStringsURL {
        slStringsFileName = stringsURL.lastPathComponent
        do {
            let fileString = try String(contentsOf: stringsURL)
            slStringsDictionary = fileString.propertyListFromStringsFileFormat() // crashes if file is incorrect format.
            translateSourceLanguage()
        } catch {
            showError("Unable to read contents of strings file")
        }
    }
}

func translateSourceLanguage() {
    tlStringsDictionary = [:] // reset
    translationFailures = [:]
    progressBar = ProgressBar(count: slStringsDictionary.count, configuration: [ProgressIndex(), ProgressTimeEstimates(), ProgressBarLine(barLength: 60)], printer: nil)
    translate(dictionary: slStringsDictionary)
}

func translate(dictionary: [String: String]) {
    for slDict in dictionary {
        let slText = slDict.value
        //print("Translating: \(slText)")
        guard let escapedText = slText.stringByAddingPercentEncoding(),
            let url = URL(string: "https://systran-systran-platform-for-language-processing-v1.p.rapidapi.com/translation/text/translate?source=\(slCode)&target=\(tlCode)&input=\(escapedText)") else { return }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: .infinity)
        request.allHTTPHeaderFields = systranHeaders

        dispatchGroup.enter()
        session.dataTask(with: request, completionHandler: { (data, response, error) in
            progressBar?.next()
            if let data = data {
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: [])
                    if let dict = json as? [String: Any] {
                        if let outputs = dict["error"] as? [String: Any],
                            let message = outputs["message"] as? String {
                            if message.contains("Route not found for service") {
                                showError("Please enter a valid language pair")
                            }
                        } else if let outputs = dict["outputs"] as? [[String: Any]],
                            let translation = outputs.first?["output"] as? String {
                            tlStringsDictionary[slDict.key] = translation
                        }
                        translationFailures.removeValue(forKey: slDict.key)
                    }
                } catch {
                    showError("Failed to parse source strings file")
                }
            } else if response != nil {
                translationFailures[slDict.key] = slDict.value
                print("response: \(response.debugDescription)")
            } else {
                translationFailures[slDict.key] = slDict.value
                print("error: \(error!.localizedDescription)")
            }
            dispatchGroup.leave()
        }).resume()
    }
    dispatchGroup.wait()

    if translationFailures.count > 0 && translationRetryCount < translationRetryMax {
        translationRetryCount += 1
        translate(dictionary: translationFailures)
    } else {
        translationComplete()
    }
}

func translationComplete() {
    progressBar?.setValue(slStringsDictionary.count)
    print(String(tlStringsDictionary.count) + " translated items. \(translationFailures.count) failures.\n") // TODO: If failures, try those again.

    if tlStringsDictionary.count == 0 {
        showError("Colt has stopped. Strings were unable to be translated")
    }

    if let tlOutputPath = tlOutputPath {
        createNewStringsFile(at: URL(fileURLWithPath: tlOutputPath)) // tlOutputPath was validated at the start
    } else if !inputPathIsDirectory {
        guard let targetURL = slStringsURL?.deletingLastPathComponent() else { showError("Unable to create new file from existing file's URL"); return }
        createNewStringsFile(at: targetURL)
    } else {
        createNewDirectory()
    }
}

// If outputPath is not set or valid, we create a new directory in
// the strings file's parent directory with the format "es.lproj".
func createNewDirectory() {
    guard let targetURL = slStringsURL?.deletingLastPathComponent().deletingLastPathComponent() else { showError("Folder has no parent directory"); return }
    let tlFolderUrl = targetURL.appendingPathComponent("\(tlCode).lproj", isDirectory: true)
    do {
        if !tlFolderUrl.absoluteString.directoryExists {
            try localFileManager.createDirectory(at: tlFolderUrl, withIntermediateDirectories: true, attributes: nil)
        }
        tlStringsURL = tlFolderUrl.appendingPathComponent(slStringsFileName, isDirectory: false)
        if let tlStringsURL = tlStringsURL {
            createNewStringsFile(at: tlStringsURL)
        }
    } catch {
        showError("Could not create translation language directory")
    }
}

func createNewStringsFile(at path: URL) {
    tlStringsURL = path
    do {
        let stringToWrite = stringsFileHeader + "\n\n" + dictionaryToStringsFileFormat(dictionary: tlStringsDictionary)
        try stringToWrite.write(to: tlStringsURL!, atomically: false, encoding: String.Encoding.utf8)
    } catch {
        showError("Was unable to create or write to strings file")
    }

    if currentSlIndex < slStringsURLs.count - 1 {
        currentSlIndex += 1
        parseSourceLanguageFile()
    } else {
        exit(EXIT_SUCCESS)
    }
}

func dictionaryToStringsFileFormat(dictionary: [String: String]) -> String {
    return dictionary.map { "\"" + $0.0.withEscapedQuotes + "\" = \"" + $0.1.withEscapedQuotes + "\";" }.joined(separator: "\n")
}

func showError(_ error: String) {
    print("⚠️  " + error)
    // if exit worthy error is found in one file, move on to the next one
    if currentSlIndex < slStringsURLs.count - 1 {
        print("Skipping file at \(slStringsURLs[currentSlIndex])")
        currentSlIndex += 1
        parseSourceLanguageFile()
    } else {
        exit(EXIT_FAILURE)
    }
}

Translate.main()
