import std.stdio;
import std.conv;

import moxana.utils.logger;

import square.one.engine;

void main(string[] args) {
	writeLog("Square One -- (C) Dylan Graham, 2018");
	writeLog("Build time: " ~ __TIMESTAMP__);

	version(LDC) {
		writeLog("Compiler: LDC2");
	}
	version(DigitalMars) {
		writeLog("Compiler: DMD2");
	}

	version(X86) {
		writeLog("Arch: x86");
		throw new Error("Square One must run on amd64 (x64)!");
	}
	version(X86_64) {
		writeLog("Arch: amd64");
	}

	version(BigEndian) {
		throw new Error("Square One is only designed for little endian.");
	}

	import core.cpuid;
	writeLog("Processor string: " ~ processor);
	writeLog("Processor vendor: " ~ vendor);
	writeLog("Cores per CPU: " ~ coresPerCPU.to!string);
	writeLog("Threads per CPU: " ~ threadsPerCPU.to!string);
	foreach(i; 0 .. numCacheLevels)
	{
		CacheInfo dc = dataCaches[i];
		writeLog("Cache " ~ to!string(i) ~ " size: " ~ to!string(dc.size) ~ "kb line: " ~ to!string(dc.lineSize) ~ "bytes");
	}

	loadDeps();

	auto engine = new SquareOneEngine();
	engine.execute();

	writeLog("Usual termination.");
}

void loadDeps() {
	import derelict.util.exception;

	{
		import derelict.glfw3.glfw3;
		writeLog("Loading GLFW3");
		DerelictGLFW3.load();
		writeLog("Loaded.");
	}

	{
		import derelict.freetype.ft;

		ShouldThrow missingFTSymbol(string symbol) {
			if(symbol == "FT_Stream_OpenBzip2")
				return ShouldThrow.No;
			else if(symbol == "FT_Get_CID_Registry_Ordering_Supplement")
				return ShouldThrow.No;
			else if(symbol == "FT_Get_CID_Is_Internally_CID_Keyed")
				return ShouldThrow.No;
			else if(symbol == "FT_Get_CID_From_Glyph_Index")
				return ShouldThrow.No;
			else
				return ShouldThrow.Yes;
		}
		DerelictFT.missingSymbolCallback = &missingFTSymbol;

		writeLog("Loading FreeType (2.6.*)");
		DerelictFT.load();
		writeLog("Loaded.");
	}

	{
		import derelict.assimp3.assimp;

		ShouldThrow missingAssimpSymbol(string symbol) {
			if(symbol == "aiReleaseExportFormatDescription")
				return ShouldThrow.No;
			else if(symbol == "aiGetImportFormatCount")
				return ShouldThrow.No;
			else if(symbol == "aiGetImportFormatDescription")
				return ShouldThrow.No;
			else
				return ShouldThrow.Yes;
		}
		DerelictASSIMP3.missingSymbolCallback = &missingAssimpSymbol;

		writeLog("Loading Assimp3");
		DerelictASSIMP3.load();
		writeLog("Loaded.");
	}

	{
		import derelict.openal.al;

		writeLog("Loading OpenAL");
		DerelictAL.load();
		writeLog("Loaded.");

	}

	{
		import derelict.enet.enet;
		
		writeLog("Loading ENet");
		DerelictENet.load();
		writeLog("Loaded.");
	}

	{
		import derelict.freeimage.freeimage;

		version(linux) {
			ShouldThrow missingFreeImageSymbol(string symbol) {
				/*if(symbol == "FreeImage_JPEGTransform")
					return ShouldThrow.No;
				else if(symbol == "FreeImage_JPEGTransformU")
					return ShouldThrow.No;
				else if(symbol == "FreeImage_JPEGCrop")
					return ShouldThrow.No;
				else if(symbol == "FreeImage_JPEGCropU")
					return ShouldThrow.No;
				else if(symbol == "FreeImage_JPEGTransformFromHandle")
					return ShouldThrow.No;
				else if(symbol == "FreeImage_JPEGTransformCombined")
					return ShouldThrow.No;
				else if(symbol == "FreeImage_JPEGTransformCombinedU")
					return ShouldThrow.No;
				else
					return ShouldThrow.Yes;*/
				return ShouldThrow.No;
			}
			DerelictFI.missingSymbolCallback = &missingFreeImageSymbol;
		}

		writeLog("Loading FreeImage");
		DerelictFI.load();
		writeLog("Loaded.");
	}
}
