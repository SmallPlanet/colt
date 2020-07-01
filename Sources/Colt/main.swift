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
    guard let _ = slStringsDictionary else { return }
    tlStringsDictionary = [:]
    for (key, value) in slStringsDictionary! {
        translate(slKey: key, slText: value) // TODO: Chanage to this returning a value and add to tlStringsDictionary
    }
    print(tlStringsDictionary! as Dictionary<String,String>)
}

struct StringTranslation: Codable {
    var orig: String
    var trans: String
}

struct SentencesObj: Codable {
    var sentence: Dictionary<String,String>
}

func translate(slKey: String, slText: String) {
    guard let escapedText = slText.stringByAddingPercentEncoding(),
        let url = URL(string: "https://translate.google.com/translate_a/single?client=gtx&sl=\(slCode)&tl=\(tlCode)&dt=t&q=\(escapedText)&dj=1") else { return }
    print("translating: \(slText)")

    let request = URLRequest(url: url)
    URLSession.shared.dataTask(with: request) { data, _, error in
        if let data = data,
            let responseText: Array = String(data: data, encoding: .utf8)?.components(separatedBy: "\""),
            responseText.count > 1 {
            tlStringsDictionary?[slKey] = responseText[1] // TODO: Move up into translateSourceLanguage()
            
//            do {
//                let product = try JSONDecoder().decode(SentencesObj.self, from: data)
//                print(product)
//            } catch {
//                print("error")
//            }
        } else {
            print(error!.localizedDescription)
            exit(EXIT_FAILURE)
        }
        sema.signal()
    }.resume()
    sema.wait()
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
