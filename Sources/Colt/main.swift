import Foundation
import ArgumentParser

struct Translate: ParsableCommand {
  
  @Argument()
  var sl: String
  
  @Argument()
  var tl: String
  
  func run() throws {
  	print("Translate from \(sl) to \(tl)")    
  }
}

Translate.main()
