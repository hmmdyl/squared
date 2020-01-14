module squareone.systems.inventory2;

import moxane.core;
import moxane.io;
import moxane.utils.math;

import dlib.math.vector;

import std.experimental.allocator.mallocator;
import std.algorithm : count;

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

@Component struct ItemInventory
{
	Entity[] slots;
	Vector!(ubyte, 2) dimensions;

	ubyte selectionX;

	Entity getSelected() { return slots[flattenIndex2D(selectionX, dimensions.y - 1, dimensions.x)]; }
}

@Component struct InventoryLocal { bool open; }

@Component struct SecondaryInventory { Vector!(ubyte, 2) dimensions; bool active; }

enum primaryUse = InventorySystem.stringof ~ ":primaryUse";
enum primaryUseDefault = MouseButton.left;
enum secondaryUse = InventorySystem.stringof ~ ":secondaryUse";
enum secondaryUseDefault = MouseButton.right;

final class InventorySystem : System
{
	private Entity target_;
	@property Entity target() { return target_; }

	this(Moxane moxane, EntityManager manager)
	{
		super(moxane, manager);

		InputManager im = moxane.services.get!InputManager;
		if(!im.hasBinding(primaryUse))
			im.setBinding(primaryUse, primaryUseDefault);
		if(!im.hasBinding(secondaryUse))
			im.setBinding(secondaryUse, secondaryUseDefault);

		im.boundKeys[primaryUse] ~= &onInput!PrimaryUse;
		im.boundKeys[secondaryUse] ~= &onInput!SecondaryUse;
	}

	~this()
	{
		InputManager im = moxane.services.get!InputManager;
		im.boundKeys[primaryUse] -= &onInput!PrimaryUse;
		im.boundKeys[secondaryUse] -= &onInput!SecondaryUse;
	}

	override void update()
	{
		auto candidates = entityManager.entitiesWith!(ItemInventory, InventoryLocal)();
		if(candidates.count == 0) return;
		target_ = candidates.front;


	}

	private void onInput(alias T)(ref InputEvent ie)
	{
		if(target_ is null) return;

		ItemInventory* inv = target_.get!ItemInventory;
		if(inv is null) return;

		Entity item = inv.getSelected;
		if(item is null) return;

		T* component = item.get!T;
		if(component is null) return;

		component.invoke();
	}
}