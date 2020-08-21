*** This project is currently in progress. ***


<img align="center" src="meta/colt_logo.png" >

# COLT - COmmand Line Translation
Colt is a command line tool that allows a developer to automate strings translations for localization. It will parse your existing file(s), translate each string to your desired language, and save them into a new file. This can be a tool for developers who do not have the resources to hire a translator, yet want to make their apps more accessible. Or, for those simply curious at how their app would look in a different language.

# Pre-Installation Instructions
### RapidAPI/SYSTRAN.io Api Key
It took some searching to find a free translation api with minimal sign up. I settled on using the SYSTRAN.io api through RapidAPI, which can be found [here on their website](https://rapidapi.com/systran/api/systran-io-translation-and-nlp). To use Colt, you must register to get a key. Click the "Sign Up" button, and after completing registration you'll see that the `X-RapidAPI-Key` value has been populated on the api page. That is the api key you will use in the following step.

### .colt File
Colt will look for the SYSTRAN.io api key in a hidden file in your user's home directory. Open any text editor and enter the following, inserting your api key value in place of `123456789abcdefg`, and save with the name `.colt` in your user's home directory (Users/yourusername/). You may be prompted that _"Names that begin with a dot are reserved for the system."_ but still use this format. It just means that your file will be hidden. If you need to find this file in the future, you can opt to show your hidden files by typing `Command + Shift + Dot`.
```
[keys]
	rapidapi = 123456789abcdefg
```

# Installation
_NOTE: These instructions will create a release build of this project on your machine so that you can use Colt from any directory._

- Clone this repo
- Open Terminal run the following commands
```
cd [path to colt directory]
swift build --configuration release
cp .build/release/colt /usr/local/bin/colt
```

# Let's Get This Party Started
Your files must be in the format used for .strings files. In this format, keys and values are separated by an equal sign, and each key-value pair is terminated with a semicolon. The value is optional—if not present, the equal sign is also omitted. The keys and values themselves are always strings enclosed in straight quotation marks. Comments may be included, delimited by `/*` and `*/`, or `//`.

To run colt, run the following in Terminal:
```
colt en es [path]
```

The argument [path] can be used two different ways:

1. Point to a **directory**, and Colt will enumerate through all the files and translate all strings files that have the format of `[sourceLanguage].proj/[name].strings` (the Xcode default). It will not find the source language file if it is in the `Base.lproj` folder. If there is a file that you would like for Colt to ignore, just add `coltIgnore` anywhere in your file name. This can be useful for things like text styles or html that doesn't need translation. Or, if you'd made any changes to the translated file that you don't want to be written over.

2. Point to a **single file**, and as long as it's in the correct strings file format, it will be translated. It does not need to have the `.strings` extension. 

### Optional Arguments
There is an optional output path argument, where you can set the destination for your translated strings file(s) to be saved. This can be used as following:

```
colt en es [path] -o [outputPath]
```

### SYSTRAN.io
Colt uses the SYSTRAN.io api for translation. A list of supported language pairs can be found here, under the Machine Translation section. https://platform.systran.net/index (FYI, if wanting to translate to Chinese, you must use the code "zh-Hans" with a capital H. It is not listed like this in the pairs supported pairs list.)

There is a disclaimer of "SYSTRAN Platform is free for small volumes and testing purposes, monthly subscriptions are available for higher volumes", however with all my testing I never hit this limit. I'm banking on your project not including Les Misérables (although maybe it should).
