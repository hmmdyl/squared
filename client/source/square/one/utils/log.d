module square.one.utils.log;

import std.file;
import std.path : buildPath;
import std.stdio;
//import colorize;

public immutable string logFilePath;

private __gshared File logFile;

enum MessageType {
	standard,
	error,
	warning
}

void writeToLog(MessageType type, string message) {
	synchronized {
		if(type == MessageType.warning) {
			//cwrite("Warning".color(fg.light_yellow, bg.init, mode.bold));
			//cwrite(": ".color(fg.init, bg.init, mode.init));
			//cwriteln(message.color(fg.init, bg.init, mode.init));
			logFile.write("Warning: ");
		}
		else if(type == MessageType.error) {
			//cwrite("Error".color(fg.light_red, bg.init, mode.bold));
			//cwrite(": ".color(fg.init, bg.init, mode.init));
			//cwriteln(message.color(fg.init, bg.init, mode.init));
			logFile.write("Error: ");
		}
		else {
			//cwrite("Message: ".color(fg.init, bg.init, mode.init));
			//cwriteln(message.color(fg.init, bg.init, mode.init));
			logFile.write("Message: ");
		}
		logFile.writeln(message);
		logFile.flush();
	}
}

shared static this() {
	logFilePath = buildPath(getcwd(), "log.txt");
	logFile = File(logFilePath, "w");
}