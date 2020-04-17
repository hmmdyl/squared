module squareone.entities.playerinventory;

import squareone.systems.inventory3;

import moxane.core;
import moxane.io;
import moxane.graphics.renderer;

import std.algorithm.searching : canFind;

void addInventory(Moxane moxane, Entity e, ubyte width, ubyte height, ubyte iconWidth = 16, ubyte iconHeight = 16)
in(e !is null)
{
	InventoryComponent* iv = e.createComponent!InventoryComponent;
	iv.inventory = new Inventory(width, height, iconWidth, iconHeight, 
								 moxane.services.get!Renderer(), "test");
}

Entity createTestItem(EntityManager em) @trusted
{
	Entity entity = new Entity(em);
	em.add(entity);
	UseScript useScript = new UseScript(em.moxane);
	entity.attachScript(useScript);
	ItemPrimaryUse* primaryUse = entity.createComponent!ItemPrimaryUse;
	primaryUse.invoke = &useScript.onPrimary;

	ItemDefinition* definition = entity.createComponent!ItemDefinition;
	definition.technicalName = "yeet";
	definition.displayName = "yeet";
	definition.maxStack = 1;

	ItemStack* stack = entity.createComponent!ItemStack;
	stack.size = 1;

	return entity;
}

class UseScript : Script
{
	this(Moxane moxane) { super(moxane); }

	override void execute() {}

	void onPrimary(const ref InputEvent ie) @trusted
	{
		import std.stdio : writeln;
		writeln(typeof(this).stringof);
	}
}