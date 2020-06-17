import Foundation
import ArgumentParser

var slCode:String = ""
var tlCode:String = ""
var slStringsURL:URL?
var tlStringsURL:URL?
let localFileManager = FileManager()
let supportedLanguageCodes:Array = ["en", "es", "fr", "it"]
var stringsFileHeader:String = ""

struct Translate: ParsableCommand {
	@Argument()
	var sl: String
  
	@Argument()
	var tl: String

	func run() throws {
        slCode = sl
        tlCode = tl
		startColt()
	}
}

func startColt() {
    guard supportedLanguageCodes.contains(slCode) else { showError("Source language is not supported."); return }
    guard supportedLanguageCodes.contains(tlCode) else { showError("Translation language is not supported."); return }
    stringsFileHeader = "/*\nThis file was translated using Colt on \(Date())\nhttps://github.com/mmwwwhahaha/colt\nSource language: \(slCode)\nTranslated to: \(tlCode)\n*/"
    findStringsFiles()
}

func findStringsFiles() {
    let currentDirectoryURL = URL(fileURLWithPath:localFileManager.currentDirectoryPath)
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
    } else if tlStringsURL == nil {
        createNewDirectory()
    } else {
        // translation already exists
    }
}

func createNewDirectory() {
    //TODO: better way to back up 2 components?
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
    print("tlStringsURL = \(tlStringsURL!)")
    do {
        try stringsFileHeader.write(to: tlStringsURL!, atomically: false, encoding: String.Encoding.utf8)
        try "\n\nStrings go here".appendLineToURL(fileURL: tlStringsURL!)
    } catch {
        print("could not create .strings file")
    }
}

func copyStringsFile(to: URL, source: URL) {
    do {
        try localFileManager.copyItem(atPath: source.absoluteString, toPath: to.absoluteString)
    } catch {
        print("copy failed")
    }
}

func showError(_ error: String) {
    print(error)
}

Translate.main()


