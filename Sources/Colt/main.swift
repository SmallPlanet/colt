import Foundation
import ArgumentParser
import Network

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


let localFileManager = FileManager()
let supportedLanguageCodes: Array = ["en", "es", "fr", "it"]
var stringsFileHeader: String = ""
let currentDirectoryURL: URL = URL(fileURLWithPath: localFileManager.currentDirectoryPath)

let dispatchGroup = DispatchGroup()



// x-rapidapi-key will be supplied from a user created text file
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
    
    let rapidApiKeyPath = URL(fileURLWithPath: localFileManager.currentDirectoryPath + "/rapid_api_key.txt")
    do {
        try rapid_api_key = String.init(contentsOf: rapidApiKeyPath)
        systranHeaders["x-rapidapi-key"] = rapid_api_key
    } catch {
        showError("API key not found. Using mine for debug")
        systranHeaders["x-rapidapi-key"] = "6368a1c70cmsh41415f22aff7cbcp1cdc9djsn47c4c53c8e2d" // TODO: REMOVE BEFORE RELEASE
        exit(EXIT_FAILURE)
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
        showError("Colt only supports OSX 10.14+")
        exit(EXIT_FAILURE)
    }
    
    //TODO: Finish the header
    //swiftlint:disable line_length
    stringsFileHeader = "/*\nThis file was translated using Colt on \(Date())\nhttps://github.com/mmwwwhahaha/colt\nSource language: \(slCode)\nTranslated to: \(tlCode)\n\n*/"

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
    
    slStringsDictionary.forEach { slDict in
        let slText = slDict.value
        guard let escapedText = slText.stringByAddingPercentEncoding(),
            let url = URL(string: "https://systran-systran-platform-for-language-processing-v1.p.rapidapi.com/translation/text/translate?source=\(slCode)&target=\(tlCode)&input=\(escapedText)") else { return }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10.0)
        request.allHTTPHeaderFields = systranHeaders
        
        dispatchGroup.enter()
        session.dataTask(with: request, completionHandler: { (data, response, error) in
            if let data = data {
                do{
                    
                    let json = try JSONSerialization.jsonObject(with: data, options: [])
                    if let dict = json as? [String: Any],
                        let outputs = dict["outputs"] as? [[String:Any]],
                        let translation = outputs.first?["output"] as? String {
                        tlStringsDictionary?[slDict.key] = translation
                    }
                } catch {
                    showError("json conversion failed")
                }
            } else if let response = response {
                print("response: \(response)")
                exit(EXIT_FAILURE)
            } else {
                print(error!.localizedDescription)
                exit(EXIT_FAILURE)
            }
            dispatchGroup.leave()
        }).resume()
    }
    
    dispatchGroup.wait()
    print(String(tlStringsDictionary?.count ?? 0) + " items.\n", tlStringsDictionary!)
    createNewDirectory()
}

func createNewDirectory() {
    //better way to back up 2 components?
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
        try stringsFileHeader.write(to: tlStringsURL!, atomically: false, encoding: String.Encoding.utf8)
        if #available(OSX 10.13, *) {
            try NSDictionary(dictionary: tlStringsDictionary!).descriptionInStringsFileFormat.write(to: tlStringsURL!, atomically: true, encoding: .utf16)
        }
    } catch {
        print("could not create .strings file")
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
    exit(EXIT_FAILURE)
}

Translate.main()
