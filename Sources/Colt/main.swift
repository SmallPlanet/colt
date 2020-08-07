import Foundation
import ArgumentParser
import Network
import Progress
import INI

var slCode: String = ""
var tlCode: String = ""
var pathToSingleFile: String?
var currentSlIndex: Int = 0
var slStringsURLs: [URL] = []
var slStringsFileName: String = ""
var slStringsURL: URL?
var tlStringsURL: URL?
var slStringsDictionary: [String:String] = [:]
var slStringsURLS: [String:URL] = [:]
var tlStringsDictionary: [String:String] = [:]
var slStrings: [String:String] = [:]
var translationFailures: [String:String] = [:]

let localFileManager = FileManager()
var stringsFileHeader: String = ""
let currentDirectoryURL: URL = URL(fileURLWithPath: localFileManager.currentDirectoryPath)

let dispatchGroup = DispatchGroup()

let sessionConfiguration = URLSessionConfiguration.default
let session = URLSession(configuration: sessionConfiguration)

// x-rapidapi-key will be supplied by the user
var rapid_api_key: String?
var systranHeaders = [
    "x-rapidapi-host": "systran-systran-platform-for-language-processing-v1.p.rapidapi.com",
    "x-rapidapi-key": ""
]

struct Translate: ParsableCommand {
	@Argument()
	var slInput: String

	@Argument()
	var tlInput: String
    
    @Option(name: .shortAndLong, help: "Path to a single file to translate.")
    var path: String?

	func run() throws {
        slCode = slInput
        tlCode = tlInput
        pathToSingleFile = path
        startColt()
	}
}

func startColt() {
    print("startColt: \(slCode) to \(tlCode)")
            
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
    
    //TODO: Finish the header
    //swiftlint:disable line_length
    stringsFileHeader = "/*\nThis file was translated using Colt on \(Date())\nhttps://github.com/mmwwwhahaha/colt\nSource language: \(slCode)\nTranslated to: \(tlCode)\n*/"

    pathToSingleFile != nil ? findSingleStringsFile() : findAllStringsFiles()
}

func findSingleStringsFile() {
    if let _ = pathToSingleFile {
        if !pathToSingleFile!.starts(with: "file://") {
            pathToSingleFile = "file://" + pathToSingleFile!
        }
        if let url = URL(string: pathToSingleFile!) {
            if url.lastPathComponent.lowercased().contains("coltignore") {
                showError("A file cannot be translated if it has 'coltIgnore' in its title")
            } else {
                slStringsURLs.append(url)
                parseSourceLanguageFile()
            }
        } else {
            showError("File cannot be found.")
        }
    }
}

func findAllStringsFiles() {
    let directoryEnumerator = localFileManager.enumerator(at: currentDirectoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

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
    translationFailures = [:]
    slStringsURL = slStringsURLs[currentSlIndex]
    if let stringsURL = slStringsURL {
        slStringsFileName = stringsURL.lastPathComponent
        do {
            let fileString = try String(contentsOf: stringsURL)
            slStringsDictionary = fileString.propertyListFromStringsFileFormat() // crashes if file is incorrect format.
            translateSourceLanguage()
        } catch {
            showError("Unable to read format of strings file")
        }
    }
}

func translateSourceLanguage() {
    tlStringsDictionary = [:] // reset
    
    var progressBar = ProgressBar(count: slStringsDictionary.count)
    
    for slDict in slStringsDictionary {
        let slText = slDict.value
        print("Translating: \(slText)")
        guard let escapedText = slText.stringByAddingPercentEncoding(),
            let url = URL(string: "https://systran-systran-platform-for-language-processing-v1.p.rapidapi.com/translation/text/translate?source=\(slCode)&target=\(tlCode)&input=\(escapedText)") else { return }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30.0)
        request.allHTTPHeaderFields = systranHeaders
        
        dispatchGroup.enter()
        session.dataTask(with: request, completionHandler: { (data, response, error) in
            progressBar.next()
            if let data = data {
                do{
                    let json = try JSONSerialization.jsonObject(with: data, options: [])
                    if let dict = json as? [String: Any] {
                        if let outputs = dict["outputs"] as? [[String:Any]],
                            let translation = outputs.first?["output"] as? String {
                            tlStringsDictionary[slDict.key] = translation
                        }
                    }
                } catch {
                    showError("Failed to parse source strings file")
                }
            } else if let response = response {
                translationFailures[slDict.key] = slDict.value
                print("response: \(response)")
            } else {
                translationFailures[slDict.key] = slDict.value
                print("error: \(error!.localizedDescription)")
            }
            dispatchGroup.leave()
        }).resume()
    }
    
    dispatchGroup.wait()
    progressBar.setValue(slStringsDictionary.count)
    print(String(tlStringsDictionary.count) + " translated items. \(translationFailures.count) failures.\n", tlStringsDictionary)
    
    if tlStringsDictionary.count == 0 {
        showError("⚠️  Colt stopped. Strings were unable to be translated")
    }
    
    if pathToSingleFile != nil {
        guard let targetURL = slStringsURL?.deletingLastPathComponent() else { return }
        tlStringsURL = targetURL.appendingPathComponent(tlCode + "_" + slStringsFileName, isDirectory: false)
        if let tlStringsURL = tlStringsURL {
            createNewStringsFile(atPath: tlStringsURL)
        }
    } else {
        createNewDirectory()
    }
}

func createNewDirectory() {
    guard let targetURL = slStringsURL?.deletingLastPathComponent().deletingLastPathComponent() else { print("no parent directory"); return }
    let tlFolderUrl = targetURL.appendingPathComponent("\(tlCode).lproj", isDirectory: true)
    do {
        try localFileManager.createDirectory(at: tlFolderUrl, withIntermediateDirectories: true, attributes: nil)
        tlStringsURL = tlFolderUrl.appendingPathComponent(slStringsFileName, isDirectory: false)
        if let tlStringsURL = tlStringsURL {
            createNewStringsFile(atPath: tlStringsURL)
        }
    } catch {
        showError("Could now create translation language directory")
    }
}

func createNewStringsFile(atPath: URL) {
    tlStringsURL = atPath
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

func dictionaryToStringsFileFormat(dictionary: [String:String]) -> String {
    return dictionary.map { "\"" + $0.0.withEscapedQuotes + " = " + $0.1.withEscapedQuotes + "\";" }.joined(separator: "\n")
}

func showError(_ error: String) {
    print(error)
    if currentSlIndex < slStringsURLs.count - 1 {
        print("Skipping file at \(slStringsURLs[currentSlIndex])")
        currentSlIndex += 1
        parseSourceLanguageFile()
    } else {
        exit(EXIT_FAILURE)
    }
}

Translate.main()
