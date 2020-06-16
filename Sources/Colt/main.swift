import Foundation
import ArgumentParser

struct Translate: ParsableCommand {
  
	@Argument()
	var sl: String
  
  // @Argument()
  // var tl: String

	// @Argument()
	// var filepath: String
  
	func run() throws {

		let localFileManager = FileManager()
		let currentDirectoryPath = localFileManager.currentDirectoryPath
        let dirEnum = localFileManager.enumerator(atPath: currentDirectoryPath)
        
        //TODO: skip hidden files
		while let file = dirEnum?.nextObject() as? String {
			if file.contains("\(sl).lproj") {
				print(file)
			}
		}
	}
}

Translate.main()
