// Rustler + Rapier passthrough NIF for the rapier_lab spike. Bare
// enough that rapier_lab-epu (the real API surface) can grow this file
// without a rewrite.

use rapier3d::prelude::*;
use rustler::Atom;

mod atoms {
    rustler::atoms! { ok }
}

/// Returns `:ok` — the NIF is loaded.
#[rustler::nif]
fn ping() -> Atom {
    atoms::ok()
}

/// Canned Rapier test: drops a unit-radius ball from 5 m onto a static
/// ground plane, steps 120 frames at 1/60 s. Returns the ball's final
/// y coordinate — should land near 1.0 (its radius; centre resting on
/// the plane).
#[rustler::nif]
fn smoke_drop() -> f32 {
    let mut rigid_bodies = RigidBodySet::new();
    let mut colliders = ColliderSet::new();
    let mut islands = IslandManager::new();
    let mut broad_phase = DefaultBroadPhase::new();
    let mut narrow_phase = NarrowPhase::new();
    let mut impulse_joints = ImpulseJointSet::new();
    let mut multibody_joints = MultibodyJointSet::new();
    let mut ccd_solver = CCDSolver::new();
    let mut query_pipeline = QueryPipeline::new();
    let mut pipeline = PhysicsPipeline::new();
    let integration_parameters = IntegrationParameters::default();
    let gravity = vector![0.0, -9.81, 0.0];
    let physics_hooks = ();
    let event_handler = ();

    let ground = ColliderBuilder::cuboid(50.0, 0.1, 50.0).build();
    colliders.insert(ground);

    let ball_rb = RigidBodyBuilder::dynamic()
        .translation(vector![0.0, 5.0, 0.0])
        .build();
    let ball_handle = rigid_bodies.insert(ball_rb);
    let ball_collider = ColliderBuilder::ball(1.0).restitution(0.5).build();
    colliders.insert_with_parent(ball_collider, ball_handle, &mut rigid_bodies);

    for _ in 0..120 {
        pipeline.step(
            &gravity,
            &integration_parameters,
            &mut islands,
            &mut broad_phase,
            &mut narrow_phase,
            &mut rigid_bodies,
            &mut colliders,
            &mut impulse_joints,
            &mut multibody_joints,
            &mut ccd_solver,
            Some(&mut query_pipeline),
            &physics_hooks,
            &event_handler,
        );
    }

    rigid_bodies[ball_handle].translation().y
}

rustler::init!("Elixir.RapierLab.Physics");
