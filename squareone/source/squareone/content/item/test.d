module squareone.content.item.test;

import moxane.core;
import moxane.graphics;
import squareone.systems.inventory2;

import derelict.opengl3.gl3;

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

    void onPrimary(const ref InputEvent ie) @trusted
    {
		if(ie.action != ButtonAction.press) return;

        import std.stdio : writeln;
        writeln("primary usage invoked!");
    }
}

private final class RenderUtils
{
	Effect effect;
	uint vao, vbo;

	this(Moxane moxane) @trusted
	{
		effect = new Effect(moxane, typeof(this).stringof);
		effect.attachAndLink(
		[
			new Shader(AssetManager.translateToAbsoluteDir("content/shaders/icon.vs.glsl"), GL_VERTEX_SHADER),
			new Shader(AssetManager.translateToAbsoluteDir("content/shaders/icon.fs.glsl"), GL_FRAGMENT_SHADER)
		]);
		effect.bind;
		effect.findUniform("Position");
        effect.findUniform("Size");
        effect.findUniform("MVP");
        effect.findUniform("Diffuse");
		effect.unbind;

        glGenVertexArrays(1, &vao);
        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        auto verts = 
        [
            Vector2f(0, 0),
            Vector2f(1, 0),
            Vector2f(1, 1),
            Vector2f(1, 1),
            Vector2f(0, 1),
            Vector2f(0, 0)
        ];
        glBufferData(GL_ARRAY_BUFFER, Vector2f.sizeof * verts.length, verts.ptr, GL_STATIC_DRAW);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
	}

	static typeof(this) instance_;
	static typeof(this) instance(Moxane moxane) @trusted
	{
		if(instance_ is null)
			instance_ = new RenderUtils(moxane);
		return instance_;
	}
}

private void onRender(Entity entity, Renderer renderer, InventoryRenderer ir, 
    ref LocalContext lc, ref uint dc, ref uint nv) @trusted
{
    RenderUtils ru = RenderUtils.instance(renderer.moxane);

	with(ru)
	{
		glBindVertexArray(vao);
        scope(exit) glBindVertexArray(0);

        glEnableVertexAttribArray(0);
        scope(exit) glDisableVertexAttribArray(0);

        effect.bind;
        scope(exit) effect.unbind;

        glActiveTexture(GL_TEXTURE0);
		effect["Position"].set(Vector2f(0, 0));
		effect["Size"].set(Vector2f(100, 100));
		Matrix4f i = lc.projection * lc.view;
		effect["MVP"].set(&i);

        scope(exit) glBindBuffer(GL_ARRAY_BUFFER, 0); 
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glVertexAttribPointer(0, 2, GL_FLOAT, false, 0 , null);

        glDrawArrays(GL_TRIANGLES, 0, 6);
	}
}

Entity createTestPlayer(EntityManager em) @trusted
{
    auto entity = new Entity(em);
    em.add(entity);
    ItemInventory* inventory = entity.createComponent!ItemInventory;
    inventory.slots = new Entity[](4);
    inventory.dimensions = Vector!(ubyte, 2)(2, 2);
    inventory.selectionX = 0;

    inventory.slots[3] = createTestItem(em);

    auto l = entity.createComponent!InventoryLocal;

    return entity;
}