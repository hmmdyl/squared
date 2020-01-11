module squareone.systems.inventory2;

import moxane.core;
import moxane.utils.math;

import std.experimental.allocator.mallocator;

@safe:

@Component struct ItemDefinition
{
	string technicalName;
	string displayName;

	ushort maxStack;
	
	void delegate() onRender;
}

@Component struct ItemStack { ushort size; }

@Component struct PrimaryUse { void delegate() invoke; }
@Component struct SecondaryUse { void delegate() invoke; }

@Component
struct ItemInventory
{
	Entity[] slots;

	private ubyte width_, height_;
	@property ubyte width() const { return width_; }
	@property ubyte height() const { return height_; }

	this(ubyte width, ubyte height)
	{
		//resize(width, height);
	}

	/+void resize(uint width, uint height)
	in { assert(width > 0, "0 width inventory invalid");
		 assert(height > 0, "0 height inventory invalid"); }
	out { assert(slots !is null, slots.stringof ~ " not allocated!"); }
	do {
		ItemStack[] newSlots = new ItemStack[](width * height);
		if(slots !is null)
		{
			foreach(x; 0 .. width_)
			{
				if(x > width) continue;
				foreach(y; 0 .. height_)
				{
					if(y > height) continue;
					newSlots[flattenIndex2D(x, y, width)] = slots[flattenIndex2D(x, y, width_)];
				}
			}
		}
		width_ = width;
		height_ = height;
		slots = newSlots;
	}+/
}

@Component
struct InventoryLocal
{

}

@Component
struct SecondaryInventory
{
	ubyte width, height;
}

final class InventorySystem : System
{
	this(Moxane moxane, EntityManager manager)
	{
		super(moxane, manager);
	}

	override void update()
	{

	}
}