module squareone.content.voxel.family;

import squareone.systems.inventory;

import moxane.core;
import moxane.io.input;

@safe abstract class VoxelItemType : IItemType
{
	private Moxane moxane_;
	@property Moxane moxane() { return moxane_; }

	enum string incToolSizeBinding = typeof(this).stringof ~ ":incTool";
	enum string decToolSizeBinding = typeof(this).stringof ~ ":decTool";
	enum incToolDefault = Keys.equal;
	enum decToolDefault = Keys.minus;

	this(Moxane moxane) in(moxane !is null)
	{
		this.moxane_ = moxane;
		InputManager im = moxane.services.get!InputManager;
		if(!im.hasBinding(incToolSizeBinding))
			im.setBinding(incToolSizeBinding, incToolDefault);
		if(!im.hasBinding(decToolSizeBinding))
			im.setBinding(decToolSizeBinding, decToolDefault);

		im.boundKeys[incToolSizeBinding] ~= &onInput;
		im.boundKeys[decToolSizeBinding] ~= &onInput;
	}

	~this()
	{
		InputManager im = moxane.services.get!InputManager;
		im.boundKeys[incToolSizeBinding] -= &onInput;
		im.boundKeys[decToolSizeBinding] -= &onInput;
	}

	protected abstract void onInput(ref InputEvent ie) {}
}

/+@safe interface IVoxelItemType : IItemType
{
	int updateToolSize(int currentSize, bool change, bool up);
}+/

/+@safe class VoxelItemFamily : IItemFamily
{
	int toolSize; /// not in block size
	private bool anyToolSelected = false;
	private IVoxelItemType type;

	Moxane moxane; /// engine reference

	string incToolSizeBinding;
	string decToolSizeBinding;

	enum incToolSizeBindingDefault = Keys.equal;
	enum decToolSizeBindingDefault = Keys.minus;

	this(Moxane moxane,
		 string incToolSizeBinding = VoxelItemFamily.stringof ~ ":incTool",
		 string decToolSizeBinding = VoxelItemFamily.stringof ~ ":decTool")
	in(moxane !is null) 
	{
		this.moxane = moxane;
		this.incToolSizeBinding = incToolSizeBinding;
		this.decToolSizeBinding = decToolSizeBinding;

		InputManager im = moxane.services.get!InputManager;
		if(!im.hasBinding(incToolSizeBinding))
			im.setBinding(incToolSizeBinding, incToolSizeBindingDefault);
		if(!im.hasBinding(decToolSizeBinding))
			im.setBinding(decToolSizeBinding, decToolSizeBindingDefault);

		im.boundKeys[incToolSizeBinding] ~= &onInput;
		im.boundKeys[decToolSizeBinding] ~= &onInput;
	}

	~this()
	{
		InputManager im = moxane.services.get!InputManager;
		im.boundKeys[incToolSizeBinding] -= &onInput;
		im.boundKeys[decToolSizeBinding] -= &onInput;
	}

	void onSelect(IItemType type, ref ItemStack stack)
	{
		IVoxelItemType vt = cast(IVoxelItemType)type;
		assert(vt !is null);

		anyToolSelected = true;
		toolSize = vt.updateToolSize(toolSize, false, true);

		type = vt;
	}

	void onDeselect(IItemType type, ref ItemStack stack)
	{
		anyToolSelected = false;
		type = null;
	}

	private void onInput(ref InputEvent ie)
	{
		if(!anyToolSelected) return;

		if(ie.bindingName == incToolSizeBinding)
			toolSize = type.updateToolSize(toolSize, true, true);
		if(ie.bindingName == decToolSizeBinding)
			toolSize = type.updateToolSize(toolSize, true, false);
	}
}+/