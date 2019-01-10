module square.one.graphics.texture2darray;

import moxana.graphics.bitmap;

import derelict.opengl3.gl3;

import std.conv : to;

class Texture2DArray {
	private uint id_, maxWidth_, maxHeight_;
	private GLenum min_, mag_;
	private bool usesMipmaps_;

	this(string[] files, DifferentSize df, GLenum minFilter, GLenum magFilter, bool generateMipmaps) {
		Bitmap[] bitmaps = new Bitmap[](files.length);

		foreach(int i, string file; files) {
			bitmaps[i] = new Bitmap(file);
		}

		uint xMax, yMax;

		foreach(Bitmap bitmap; bitmaps) {
			xMax = bitmap.width > xMax ? bitmap.width : xMax;
			yMax = bitmap.height > yMax ? bitmap.height : yMax;
		}

		foreach(int i, Bitmap bitmap; bitmaps) {
			if(!(bitmap.width == xMax && bitmap.height == yMax)) {
				if(df == DifferentSize.shouldThrow) { 
					throw new Exception(files[i] ~ " is of [" ~ 
						to!string(bitmap.width) ~ ", " ~ to!string(bitmap.height) ~ "] not [" ~
						to!string(xMax) ~ ", " ~ to!string(yMax) ~ "] as required."); 
				} else {
					bitmap.resize(xMax, yMax, ImageFilter.bicubic);
				}
			}
		}

		enable();
		glGenTextures(1, &id_);
		bind();

		maxWidth_ = xMax;
		maxHeight_ = yMax;
		min_ = minFilter;
		mag_ = magFilter;
		usesMipmaps_ = generateMipmaps;

		glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, min_);
		glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, mag_);
		glTexImage3D(GL_TEXTURE_2D_ARRAY, 0, cast(int)GL_RGBA, cast(int)xMax, cast(int)yMax, cast(int)files.length, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);

		foreach(int i, Bitmap bitmap; bitmaps) {
			bitmap.ensure32Bits();
			glTexSubImage3D(GL_TEXTURE_2D_ARRAY, 0, 0, 0, i, xMax, yMax, 1, GL_BGRA, GL_UNSIGNED_BYTE, bitmap.data);
		}

		if(generateMipmaps)
			glGenerateMipmap(GL_TEXTURE_2D_ARRAY);

		bitmaps = null;

		unbind();
		disable();
	}

	static void enable() {
		glEnable(GL_TEXTURE_2D_ARRAY);
	}

	static void disable() {
		glDisable(GL_TEXTURE_2D_ARRAY);
	}

	void bind() {
		glBindTexture(GL_TEXTURE_2D_ARRAY, id);
	}

	void unbind() {
		glBindTexture(GL_TEXTURE_2D_ARRAY, 0);
	}

	@property uint id() { return id_; }
	@property uint maxWidth() { return maxWidth_; }
	@property uint maxHeight() { return maxHeight_; }

	@property GLenum minification() { return min_; }
	@property GLenum magnification() { return mag_; }

	@property bool usesMipmaps() { return usesMipmaps_; }
}

enum DifferentSize {
	shouldThrow,
	shouldResize
}