#pragma once

#include "btBulletDynamicsCommon.h"
#include "btBulletCollisionCommon.h"

class DbvtBroadphaseGlue {
public:
	DbvtBroadphaseGlue();
	~DbvtBroadphaseGlue();

	static DbvtBroadphaseGlue * create();
	static void destroy(DbvtBroadphaseGlue * n);

	btBroadphaseInterface * native;
};

class DefaultCollisionConfigurationGlue {
public:
	DefaultCollisionConfigurationGlue();
	~DefaultCollisionConfigurationGlue();

	static DefaultCollisionConfigurationGlue * create();
	static void destroy(DefaultCollisionConfigurationGlue * n);

	btDefaultCollisionConfiguration * native;
};

class CollisionDispatcherGlue {
public:
	CollisionDispatcherGlue(DefaultCollisionConfigurationGlue * dcc);
	~CollisionDispatcherGlue();

	static CollisionDispatcherGlue * create(DefaultCollisionConfigurationGlue * dcc);
	static void destroy(CollisionDispatcherGlue * n);

	btCollisionDispatcher * native;
};

class SequentialImpulseConstraintSolverGlue {
public:
	SequentialImpulseConstraintSolverGlue();
	~SequentialImpulseConstraintSolverGlue();

	static SequentialImpulseConstraintSolverGlue * create();
	static void destroy(SequentialImpulseConstraintSolverGlue * n);

	btSequentialImpulseConstraintSolver * native;
};

class DiscreteDynamicsWorldGlue {
public:
	DiscreteDynamicsWorldGlue(CollisionDispatcherGlue * dispatcher,
		DbvtBroadphaseGlue * broadphaseInterface, SequentialImpulseConstraintSolverGlue * solver, DefaultCollisionConfigurationGlue * collisionConfig);
	~DiscreteDynamicsWorldGlue();

	static DiscreteDynamicsWorldGlue * create(CollisionDispatcherGlue * dispatcher,
		DbvtBroadphaseGlue * broadphaseInterface, SequentialImpulseConstraintSolverGlue * solver, DefaultCollisionConfigurationGlue * collisionConfig);
	static void destroy(DiscreteDynamicsWorldGlue * n);

	void setGravity(float* v);
	float* getGravity();

	btDiscreteDynamicsWorld * native;
};

struct TransformGlue {
public:
	TransformGlue(float *matrix, float *origin);

	static TransformGlue create(float *matrix, float *origin);

	float * getBasis();
	float * getOrigin();

	btTransform native;
};

class DefaultMotionStateGlue {
public:
	DefaultMotionStateGlue(TransformGlue startTrans, TransformGlue centerOfMassOffset);
	~DefaultMotionStateGlue();

	static DefaultMotionStateGlue * create(TransformGlue startTrans, TransformGlue centerOfMassOffset);
	static void destroy(DefaultMotionStateGlue * n);

	btDefaultMotionState * native;
};

class CollisionShapeGlue {
public:
	CollisionShapeGlue();
	CollisionShapeGlue(btCollisionShape * native);
	~CollisionShapeGlue();

	static void destroy(CollisionShapeGlue* glue);

	btCollisionShape * native;
};

class StaticPlaneShapeGlue : CollisionShapeGlue {
public:
	StaticPlaneShapeGlue(float *normal, float planeConstant);
	~StaticPlaneShapeGlue();

	static StaticPlaneShapeGlue* create(float *normal, float planeConstant);
	static void destroy(StaticPlaneShapeGlue* glue);
};