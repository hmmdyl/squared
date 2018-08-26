#include "stdafx.h"
#include "classes.h"

DbvtBroadphaseGlue::DbvtBroadphaseGlue()
{
	native = new btDbvtBroadphase();
}

DbvtBroadphaseGlue::~DbvtBroadphaseGlue()
{
	delete native;
}

DbvtBroadphaseGlue * DbvtBroadphaseGlue::create()
{
	return new DbvtBroadphaseGlue();
}

void DbvtBroadphaseGlue::destroy(DbvtBroadphaseGlue * n)
{
	delete n;
}

DefaultCollisionConfigurationGlue::DefaultCollisionConfigurationGlue()
{
	native = new btDefaultCollisionConfiguration();
}

DefaultCollisionConfigurationGlue::~DefaultCollisionConfigurationGlue()
{
	delete native;
}

DefaultCollisionConfigurationGlue * DefaultCollisionConfigurationGlue::create()
{
	return new DefaultCollisionConfigurationGlue();
}

void DefaultCollisionConfigurationGlue::destroy(DefaultCollisionConfigurationGlue * n)
{
	delete n;
}

CollisionDispatcherGlue::CollisionDispatcherGlue(DefaultCollisionConfigurationGlue * dcc)
{
	native = new btCollisionDispatcher(dcc->native);
}

CollisionDispatcherGlue::~CollisionDispatcherGlue()
{
	delete native;
}

CollisionDispatcherGlue * CollisionDispatcherGlue::create(DefaultCollisionConfigurationGlue * dcc)
{
	return new CollisionDispatcherGlue(dcc);
}

void CollisionDispatcherGlue::destroy(CollisionDispatcherGlue * n)
{
	delete n;
}

SequentialImpulseConstraintSolverGlue::SequentialImpulseConstraintSolverGlue()
{
	native = new btSequentialImpulseConstraintSolver();
}

SequentialImpulseConstraintSolverGlue::~SequentialImpulseConstraintSolverGlue()
{
	delete native;
}

SequentialImpulseConstraintSolverGlue * SequentialImpulseConstraintSolverGlue::create()
{
	return new SequentialImpulseConstraintSolverGlue();
}

void SequentialImpulseConstraintSolverGlue::destroy(SequentialImpulseConstraintSolverGlue * n)
{
	delete n;
}

DiscreteDynamicsWorldGlue::DiscreteDynamicsWorldGlue(CollisionDispatcherGlue * dispatcher, DbvtBroadphaseGlue * broadphaseInterface, SequentialImpulseConstraintSolverGlue * solver, DefaultCollisionConfigurationGlue * collisionConfig)
{
	native = new btDiscreteDynamicsWorld(dispatcher->native, broadphaseInterface->native, solver->native, collisionConfig->native);
}

DiscreteDynamicsWorldGlue::~DiscreteDynamicsWorldGlue()
{
	delete native;
}

DiscreteDynamicsWorldGlue * DiscreteDynamicsWorldGlue::create(CollisionDispatcherGlue * dispatcher, DbvtBroadphaseGlue * broadphaseInterface, SequentialImpulseConstraintSolverGlue * solver, DefaultCollisionConfigurationGlue * collisionConfig)
{
	return new DiscreteDynamicsWorldGlue(dispatcher, broadphaseInterface, solver, collisionConfig);
}

void DiscreteDynamicsWorldGlue::destroy(DiscreteDynamicsWorldGlue * n)
{
	delete n;
}

void DiscreteDynamicsWorldGlue::setGravity(float* v)
{
	native->setGravity(btVector3(v[0], v[1], v[2]));
}

float* DiscreteDynamicsWorldGlue::getGravity()
{
	btVector3 v = native->getGravity();
	return &v.m_floats[0];
}

TransformGlue::TransformGlue(float * matrix, float * origin)
{
	native = btTransform(
		btMatrix3x3(
			matrix[0], matrix[1], matrix[2],
			matrix[3], matrix[4], matrix[5],
			matrix[6], matrix[7], matrix[8]
		),
		btVector3(origin[0], origin[1], origin[2]));
}

TransformGlue TransformGlue::create(float * matrix, float * origin)
{
	return TransformGlue(matrix, origin);
}

float * TransformGlue::getBasis()
{
	float arr[9];
	btMatrix3x3 basis = native.getBasis();
	arr[0] = basis[0][0];
	arr[1] = basis[0][1];
	arr[2] = basis[0][2];
	arr[3] = basis[1][0];
	arr[4] = basis[1][1];
	arr[5] = basis[1][2];
	arr[6] = basis[2][0];
	arr[7] = basis[2][1];
	arr[8] = basis[2][2];
	return &arr[0];
}

float * TransformGlue::getOrigin()
{
	btVector3 origin = native.getOrigin();
	return &origin.m_floats[0];
}

DefaultMotionStateGlue::DefaultMotionStateGlue(TransformGlue startTrans, TransformGlue centerOfMassOffset)
{
	native = new btDefaultMotionState(startTrans.native, centerOfMassOffset.native);
}

DefaultMotionStateGlue::~DefaultMotionStateGlue()
{
	delete native;
}

DefaultMotionStateGlue * DefaultMotionStateGlue::create(TransformGlue startTrans, TransformGlue centerOfMassOffset)
{
	return new DefaultMotionStateGlue(startTrans, centerOfMassOffset);
}

void DefaultMotionStateGlue::destroy(DefaultMotionStateGlue * n)
{
	delete n;
}

CollisionShapeGlue::CollisionShapeGlue()
{
}

CollisionShapeGlue::CollisionShapeGlue(btCollisionShape *native)
{
	this->native = native;
}

CollisionShapeGlue::~CollisionShapeGlue()
{
	delete native;
}

void CollisionShapeGlue::destroy(CollisionShapeGlue * glue)
{
	delete glue;
}

StaticPlaneShapeGlue::StaticPlaneShapeGlue(float * normal, float planeConstant)
	: CollisionShapeGlue()
{
	native = new btStaticPlaneShape(btVector3(normal[0], normal[1], normal[2]), planeConstant);
}

StaticPlaneShapeGlue::~StaticPlaneShapeGlue()
{
}

StaticPlaneShapeGlue* StaticPlaneShapeGlue::create(float * normal, float planeConstant)
{
	return new StaticPlaneShapeGlue(normal, planeConstant);
}

void StaticPlaneShapeGlue::destroy(StaticPlaneShapeGlue * glue)
{
	delete glue;
}
