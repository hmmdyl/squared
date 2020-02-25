module squareone.content.item.test;

import moxane.core;
import moxane.graphics.renderer;
import squareone.systems.inventory2;

import dlib.math;

@safe:

Entity createTestItem(EntityManager em) @trusted
{
    auto entity = new Entity(em);
    em.add(entity);
    auto useScript = new UseScript(em.moxane);
    entity.attachScript(useScript);
    PrimaryUse* primaryUse = entity.createComponent!PrimaryUse;
    primaryUse.invoke = &useScript.onPrimary;

    auto definition = entity.createComponent!ItemDefinition;
    definition.technicalName = "yeet";
    definition.displayName = "yeet";
    definition.maxStack = 1;

    import std.functional : toDelegate;
    definition.onRender = toDelegate(&onRender);

    auto stack = entity.createComponent!ItemStack;
    stack.size = 1;

    return entity;
}

class UseScript : Script
{
    this(Moxane moxane) { super(moxane); }

    override void execute()
    {
    }

    void onPrimary() @trusted
    {
        import std.stdio : writeln;
        writeln("primary usage invoked!");
    }
}

private void onRender(Entity entity, Renderer renderer, InventoryRenderer ir, 
    ref LocalContext lc, ref uint dc, ref uint nv) @trusted
{
    
}

Entity createTestPlayer(EntityManager em) @trusted
{
    auto entity = new Entity(em);
    em.add(entity);
    ItemInventory* inventory = entity.createComponent!ItemInventory;
    inventory.slots = new Entity[](1);
    inventory.dimensions = Vector!(ubyte, 2)(1, 1);
    inventory.selectionX = 0;

    inventory.slots[0] = createTestItem(em);

    auto l = entity.createComponent!InventoryLocal;

    return entity;
}