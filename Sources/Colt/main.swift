import Foundation
import ArgumentParser

var slCode: String = ""
var tlCode: String = ""
var slStringsURL: URL?
var tlStringsURL: URL?
var slStringsDictionary: Dictionary<String, String>?
var tlStringsDictionary: Dictionary<String, String>?
var slStrings: KeyValuePairs<String, String> = [:]
let localFileManager = FileManager()
let supportedLanguageCodes: Array = ["en", "es", "fr", "it"]
var stringsFileHeader: String = ""

let localURLSession = URLSession(configuration: URLSessionConfiguration.default)
var sema = DispatchSemaphore( value: 0 )

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

//var isRunning = false
//let runLoop = RunLoop.current
//while isRunning == true {
//    print("waiting...")
//    runLoop.run(until: Date.distantFuture)
//}

func startColt() {
    print("startColt: \(slCode) to \(tlCode)")
    guard supportedLanguageCodes.contains(slCode) else { showError("Source language is not supported."); return }
    guard supportedLanguageCodes.contains(tlCode) else { showError("Translation language is not supported."); return }
    
    // TODO: Check for network

    //TODO: Finish the header
    //swiftlint:disable line_length
    stringsFileHeader = "/*\nThis file was translated using Colt on \(Date())\nhttps://github.com/mmwwwhahaha/colt\nSource language: \(slCode)\nTranslated to: \(tlCode)\n*/"

    findStringsFiles()
}

func findStringsFiles() {
    let currentDirectoryURL = URL(fileURLWithPath: localFileManager.currentDirectoryPath)
    let directoryEnumerator = localFileManager.enumerator(at: currentDirectoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

    while let fileURL = directoryEnumerator?.nextObject() as? URL, slStringsURL == nil || tlStringsURL == nil {
        if fileURL.absoluteString.contains("\(slCode).lproj") && fileURL.absoluteString.contains(".strings") {
            slStringsURL = fileURL
        } else if fileURL.absoluteString.contains("\(tlCode).lproj") && fileURL.absoluteString.contains(".strings") {
            tlStringsURL = fileURL
        }
    }
    
    if slStringsURL == nil {
        showError("Localization folder cannot be found. Please specify a valid source language")
        // TODO: exit
    } else {
        parseSourceLanguageFile()
    }
}

func parseSourceLanguageFile() {
    if let stringsUrl = slStringsURL {
        guard let dictionary = NSDictionary(contentsOf: stringsUrl) else { print("failed"); exit(EX_DATAERR) }
        slStringsDictionary = dictionary as? Dictionary // converting to Dictionary so we can set types
        translateSourceLanguage()
    }
}

func translateSourceLanguage() {
    guard let slStringsDictionary = slStringsDictionary else { return }
    tlStringsDictionary = [:]
    for (key, value) in slStringsDictionary {
//        if let translatedText = translate(slText: value) {
//            tlStringsDictionary?[key] = translatedText
//        }
        
        let randomSeconds = Int.random(in: 1...3)
        let randomMillisecond = Int.random(in: 0...1000)
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(randomSeconds) + .milliseconds(randomMillisecond)){
            if let translatedText = translate(slText: value) {
                tlStringsDictionary?[key] = translatedText
            }
            sema.signal()
        }
        sema.wait()
    }
    print(String(tlStringsDictionary?.count ?? 0) + " items.\n", tlStringsDictionary! as AnyObject)
    //exit(EX_OK) // TEMP
}

func translate(slText: String) -> String? {
    guard let escapedText = slText.stringByAddingPercentEncoding(),
        let url = URL(string: "https://translate.google.com/translate_a/single?client=gtx&sl=\(slCode)&tl=\(tlCode)&dt=t&q=\(escapedText)") else { return nil }
    print("translating: \(slText)")

    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/11.1.2 Safari/605.1.15"]
    //sessionConfiguration.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"]
        
    var translatedText: String?
    let request = URLRequest(url: url)
    let session = URLSession.init(configuration: sessionConfiguration)
    
    session.dataTask(with: request) { data, response, error in
        if let data = data,
            let responseText: Array = String(data: data, encoding: .utf8)?.components(separatedBy: "\""),
            responseText.count > 1 {
            translatedText = responseText[1]
            if translatedText?.contains("-//W3C//DTD HTML") ?? false {
                print("*** BLOCKED ***")
                exit(EXDEV)
            }
        } else if let response = response {
            print("response: \(response)")
        } else {
            print(error!.localizedDescription)
            exit(EXIT_FAILURE)
        }
        sema.signal()
    }.resume()
    sema.wait()
    return translatedText
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
    tlStringsURL = folderUrl.appendingPathComponent("Localizable.strings", isDirectory: false)
    guard tlStringsURL != nil else { return }
    do {
        try stringsFileHeader.write(to: tlStringsURL!, atomically: false, encoding: String.Encoding.utf8)
        try "\n\nStrings go here".appendLineToURL(fileURL: tlStringsURL!)
    } catch {
        print("could not create .strings file")
    }
}


//
//func copyStringsFile(to: URL, source: URL) {
//    do {
//        try localFileManager.copyItem(atPath: source.absoluteString, toPath: to.absoluteString)
//    } catch {
//        print("copy failed")
//    }
//}

func showError(_ error: String) {
    print(error)
    exit(EXIT_FAILURE)
}

Translate.main()

//TODO: Move to Extensions file

extension String {
   func appendLineToURL(fileURL: URL) throws {
        try (self + "\n").appendToURL(fileURL: fileURL)
    }

    func appendToURL(fileURL: URL) throws {
        let data = self.data(using: String.Encoding.utf8)!
        try data.append(fileURL: fileURL)
    }
    
    func stringByAddingPercentEncoding() -> String? {
      let unreserved = "-._~/?"
      let allowed = NSMutableCharacterSet.alphanumeric()
      allowed.addCharacters(in: unreserved)
      return addingPercentEncoding(withAllowedCharacters: allowed as CharacterSet)
    }
}

extension Data {
    func append(fileURL: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: fileURL, options: .atomic)
        }
    }
}
