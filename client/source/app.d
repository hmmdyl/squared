import std.stdio;
import std.conv;
import colorize;

import square.one.engine;

void main(string[] args) {
	cwriteln();
	cwriteln("----------------------- SQUARE ONE -----------------------");
	cwriteln();
	cwriteln("(C) 2017, SpireDev");
	cwriteln("This game is under development by Dylan Graham (djg_0).");
	cwriteln("x64 is the only architecture supported.");
	cwriteln();
	cwriteln("----------------------------------------------------------");
	cwriteln();
	cwrite("Build time: ".color(fg.light_red));
	cwriteln(__TIMESTAMP__.color(fg.light_red));
	cwriteln();

	cwrite("Square One".color(fg.light_blue));
	cwriteln(" in Dlang!".color(fg.init));

	version(LDC) {
		cwriteln("Compiler: LDC2".color(fg.init));
	}
	version(DigitalMars) {
		cwriteln("Compiler: DMD2".color(fg.init));
	}

	version(X86) {
		cwriteln("Architecture: x86".color(fg.light_red));
		throw new Error("Square One must run on amd64 (x64)!");
	}
	version(X86_64) {
		cwriteln("Architecture: amd64".color(fg.init));
	}

	version(BigEndian) {
		throw new Error("Square One is only designed for little endian.");
	}

	import core.cpuid;
	cwriteln(("Processor string: " ~ processor).color(fg.init));
	cwriteln(("Processor vendor: " ~ vendor).color(fg.init));
	cwriteln(("# cores per CPU: " ~ coresPerCPU.to!string).color(fg.init));
	cwriteln(("# threads per CPU: " ~ threadsPerCPU.to!string).color(fg.init));

	scope(exit) cwriteln();

	loadDeps();

	SquareOneEngine engine = new SquareOneEngine;
	engine.execute();
	delete engine;
}

void loadDeps() {
	import derelict.util.exception;

	{
		import derelict.glfw3.glfw3;
		cwriteln("Loading GLFW3");
		DerelictGLFW3.load();
		cwriteln("Loaded GLFW3".color(fg.light_green));
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

		cwriteln("Loading FreeType (2.6 something)");
		DerelictFT.load();
		cwriteln("Loaded FreeType".color(fg.light_green));
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

		cwriteln("Loading Assimp3");
		DerelictASSIMP3.load();
		cwriteln("Loaded Assimp".color(fg.light_green));
	}

	{
		import derelict.openal.al;

		cwriteln("Loading OpenAL");
		DerelictAL.load();
		cwriteln("Loaded OpenAL".color(fg.light_green));

	}

	{
		import derelict.enet.enet;
		
		cwriteln("Loading ENet");
		DerelictENet.load();
		cwriteln("Loaded ENet".color(fg.light_green));
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

		cwriteln("Loading FreeImage");
		DerelictFI.load();
		cwriteln("Loaded FreeImage".color(fg.light_green));
	}

	{
		import derelict.ode.ode;
		cwriteln("Loading Open Dynamics Engine");

		ShouldThrow missingODESymbol(string symbol) {
			switch(symbol) {
				case "dGeomTriMeshDataGet": return ShouldThrow.No;
				default: return ShouldThrow.Yes;
			}
		}

		DerelictODE.missingSymbolCallback = &missingODESymbol;
		//DerelictODE.load;
		cwriteln("Loaded Open Dynamics Engine".color(fg.light_green));
	}
}
