import Foundation
import ArgumentParser
import Network
import Progress

var slCode: String = ""
var tlCode: String = ""
var currentSlIndex: Int = 0
var slStringsURLs: [URL] = []
var slStringsFileName: String?
var slStringsURL: URL?
var tlStringsURL: URL?
var slStringsDictionary: Dictionary<String, String>?
var slStringsURLS: Dictionary<String, URL>?
var tlStringsDictionary: Dictionary<String, String>?
var slStrings: KeyValuePairs<String, String> = [:]
var translationFailures: [String] = []

let localFileManager = FileManager()
let supportedLanguageCodes: Array = ["en", "es", "fr", "it"]
var stringsFileHeader: String = ""
let currentDirectoryURL: URL = URL(fileURLWithPath: localFileManager.currentDirectoryPath)

let dispatchGroup = DispatchGroup()

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

	func run() throws {
        slCode = slInput
        tlCode = tlInput
		startColt()
	}
}

func startColt() {
    print("startColt: \(slCode) to \(tlCode)")
    guard supportedLanguageCodes.contains(slCode) else { showError("Source language is not supported."); return }
    guard supportedLanguageCodes.contains(tlCode) else { showError("Translation language is not supported."); return }
    
    // only working within xcode at the moment
//    let apiKey = ProcessInfo.processInfo.environment["RAPIDAPI_KEY"] // ⚠️ only works in Xcode
//    print(apiKey)
//    
//    return
        
    // look in home directory and use a .hidden file (.colt) - can be used with multiple projects
    let rapidApiKeyPath = URL(fileURLWithPath: localFileManager.currentDirectoryPath + "/rapid_api_key.txt")
    do {
        try rapid_api_key = String.init(contentsOf: rapidApiKeyPath)
        systranHeaders["x-rapidapi-key"] = rapid_api_key
    } catch {
        systranHeaders["x-rapidapi-key"] = "6368a1c70cmsh41415f22aff7cbcp1cdc9djsn47c4c53c8e2d" // TODO: REMOVE BEFORE RELEASE. TEMP FOR RUNNING IN XCODE
        //showError("RapidAPI key not found") // TODO: UNCOMMENT BEFORE RELEASE
    }
    
    // Check for network
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
        monitor.pathUpdateHandler = nil // remove after use?
    } else {
        // just let 'em through
        showError("Colt only supports OSX 10.14+")
        exit(EXIT_FAILURE)
    }
    
    //TODO: Finish the header
    //swiftlint:disable line_length
    stringsFileHeader = "/*\nThis file was translated using Colt on \(Date())\nhttps://github.com/mmwwwhahaha/colt\nSource language: \(slCode)\nTranslated to: \(tlCode)\n*/"

    findStringsFiles()
}

func findStringsFiles() {
    let directoryEnumerator = localFileManager.enumerator(at: currentDirectoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

    while let fileURL = directoryEnumerator?.nextObject() as? URL, slStringsURL == nil || tlStringsURL == nil {
        if fileURL.absoluteString.contains("\(slCode).lproj") && fileURL.absoluteString.contains(".strings") {
            slStringsURLs.append(fileURL)
        } else if fileURL.absoluteString.contains("\(tlCode).lproj") && fileURL.absoluteString.contains(".strings") {
            tlStringsURL = fileURL
        }
    }
    
    if slStringsURLs.count == 0 {
        showError("Localization folder cannot be found. Please specify a valid source language")
        exit(EXIT_FAILURE)
    } else {
        parseSourceLanguageFile()
    }
}

func parseSourceLanguageFile() {
    slStringsURL = slStringsURLs[currentSlIndex]
    slStringsFileName = slStringsURL?.lastPathComponent
    if let stringsUrl = slStringsURL {
        // is there another solution where I can use Dictionary?
        // string - property list from strings file format
        guard let dictionary = NSDictionary(contentsOf: stringsUrl) else { showError("Failed to create dictionary from strings file"); exit(EX_DATAERR) }
        slStringsDictionary = dictionary as? Dictionary // converting to Dictionary so we can set types
        translateSourceLanguage()
    }
}

let sessionConfiguration = URLSessionConfiguration.default
let session = URLSession(configuration: sessionConfiguration)

func translateSourceLanguage() {
    guard let slStringsDictionary = slStringsDictionary else { return }
    tlStringsDictionary = [:]
    
    var progressBar = ProgressBar(count: slStringsDictionary.count)
    
    slStringsDictionary.forEach { slDict in
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
                    if let dict = json as? [String: Any],
                        let outputs = dict["outputs"] as? [[String:Any]],
                        let translation = outputs.first?["output"] as? String {
                        tlStringsDictionary?[slDict.key] = translation
                    }
                } catch {
                    showError("Failed to parse source strings file")
                }
            } else if let response = response {
                print("response: \(response)")
                translationFailures.append(slText)
            } else {
                print(error!.localizedDescription)
                translationFailures.append(slText)
            }
            dispatchGroup.leave()
        }).resume()
    }
    
    dispatchGroup.wait()
    progressBar.next() // why do I need this one to complete?
    print(String(tlStringsDictionary?.count ?? 0) + " translated items. \(translationFailures.count) failures.\n", tlStringsDictionary!)
    createNewDirectory()
}

func createNewDirectory() {
    //TODO: Better way to guarantee this directory is ok
    // Support multiple directory structures
    guard let targetURL = slStringsURL?.deletingLastPathComponent().deletingLastPathComponent() else { print("no parent directory"); return }
    let tlFolderUrl = targetURL.appendingPathComponent("\(tlCode).lproj", isDirectory: true)
    do {
        try localFileManager.createDirectory(at: tlFolderUrl, withIntermediateDirectories: true, attributes: nil)
        createNewStringsFile(folderUrl: tlFolderUrl)
    } catch {
        print("could not create directory")
    }
}

func createNewStringsFile(folderUrl: URL) {
    tlStringsURL = folderUrl.appendingPathComponent(slStringsFileName ?? "Localizable.strings", isDirectory: false)
    guard tlStringsURL != nil else { return }
    do {
        let stringToWrite = stringsFileHeader + "\n\n" + NSDictionary(dictionary: tlStringsDictionary!).descriptionInStringsFileFormat // is this my unicode nemesis?
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
