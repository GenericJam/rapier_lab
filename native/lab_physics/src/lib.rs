// rapier_lab-0us: real NIF surface. A stateful physics world lives
// behind a ResourceArc<Mutex<World>>; the Elixir side calls world_new,
// add_body (ball | cuboid), apply_impulse, step, transforms — enough
// to drive one Filament viewport with real physics per tick.

use rapier3d::prelude::*;
use rustler::{Atom, Encoder, Env, NifResult, ResourceArc, Term};
use std::sync::Mutex;

mod atoms {
    rustler::atoms! { ok }
}

pub struct WorldRes {
    inner: Mutex<World>,
}

#[rustler::resource_impl]
impl rustler::Resource for WorldRes {}

pub struct World {
    rigid_bodies: RigidBodySet,
    colliders: ColliderSet,
    islands: IslandManager,
    broad_phase: DefaultBroadPhase,
    narrow_phase: NarrowPhase,
    impulse_joints: ImpulseJointSet,
    multibody_joints: MultibodyJointSet,
    ccd_solver: CCDSolver,
    query_pipeline: QueryPipeline,
    pipeline: PhysicsPipeline,
    integration_parameters: IntegrationParameters,
    gravity: Vector<Real>,
    bodies: Vec<RigidBodyHandle>,
}

impl World {
    fn new() -> Self {
        World {
            rigid_bodies: RigidBodySet::new(),
            colliders: ColliderSet::new(),
            islands: IslandManager::new(),
            broad_phase: DefaultBroadPhase::new(),
            narrow_phase: NarrowPhase::new(),
            impulse_joints: ImpulseJointSet::new(),
            multibody_joints: MultibodyJointSet::new(),
            ccd_solver: CCDSolver::new(),
            query_pipeline: QueryPipeline::new(),
            pipeline: PhysicsPipeline::new(),
            integration_parameters: IntegrationParameters::default(),
            gravity: vector![0.0, -9.81, 0.0],
            bodies: Vec::new(),
        }
    }

    fn step(&mut self, dt: f32) {
        self.integration_parameters.dt = dt;
        let hooks = ();
        let events = ();
        self.pipeline.step(
            &self.gravity,
            &self.integration_parameters,
            &mut self.islands,
            &mut self.broad_phase,
            &mut self.narrow_phase,
            &mut self.rigid_bodies,
            &mut self.colliders,
            &mut self.impulse_joints,
            &mut self.multibody_joints,
            &mut self.ccd_solver,
            Some(&mut self.query_pipeline),
            &hooks,
            &events,
        );
    }
}

#[rustler::nif]
fn ping() -> Atom {
    atoms::ok()
}

/// Creates a new physics world with gravity (0, -9.81, 0) and a static
/// wide ground plane at y = 0. Returns a resource handle callers hold
/// onto for the lifetime of the world.
#[rustler::nif]
fn world_new() -> ResourceArc<WorldRes> {
    let mut world = World::new();

    // Static ground (100 x 0.2 x 100 m, top surface at y = 0).
    let ground = ColliderBuilder::cuboid(50.0, 0.1, 50.0)
        .translation(vector![0.0, -0.1, 0.0])
        .build();
    world.colliders.insert(ground);

    ResourceArc::new(WorldRes {
        inner: Mutex::new(world),
    })
}

/// Adds a dynamic ball of `radius` at world `(x, y, z)`. Returns the
/// body index (Elixir-side identifier — u32; kept in insertion order).
#[rustler::nif]
fn add_ball(res: ResourceArc<WorldRes>, x: f32, y: f32, z: f32, radius: f32) -> u32 {
    let mut world = res.inner.lock().unwrap();
    let World {
        rigid_bodies,
        colliders,
        bodies,
        ..
    } = &mut *world;

    let rb = RigidBodyBuilder::dynamic()
        .translation(vector![x, y, z])
        .build();
    let handle = rigid_bodies.insert(rb);
    let collider = ColliderBuilder::ball(radius).restitution(0.4).build();
    colliders.insert_with_parent(collider, handle, rigid_bodies);
    bodies.push(handle);
    (bodies.len() - 1) as u32
}

/// Adds a dynamic cuboid (half-extents hx, hy, hz) at world `(x, y, z)`.
#[rustler::nif]
fn add_cuboid(
    res: ResourceArc<WorldRes>,
    x: f32,
    y: f32,
    z: f32,
    hx: f32,
    hy: f32,
    hz: f32,
) -> u32 {
    let mut world = res.inner.lock().unwrap();
    let World {
        rigid_bodies,
        colliders,
        bodies,
        ..
    } = &mut *world;

    let rb = RigidBodyBuilder::dynamic()
        .translation(vector![x, y, z])
        .build();
    let handle = rigid_bodies.insert(rb);
    let collider = ColliderBuilder::cuboid(hx, hy, hz).restitution(0.4).build();
    colliders.insert_with_parent(collider, handle, rigid_bodies);
    bodies.push(handle);
    (bodies.len() - 1) as u32
}

/// Adds a linear-velocity impulse (m/s) to a body's centre of mass.
#[rustler::nif]
fn apply_impulse(
    res: ResourceArc<WorldRes>,
    body_id: u32,
    ix: f32,
    iy: f32,
    iz: f32,
) -> NifResult<Atom> {
    let mut world = res.inner.lock().unwrap();
    let Some(handle) = world.bodies.get(body_id as usize).copied() else {
        return Ok(atoms::ok());
    };
    if let Some(rb) = world.rigid_bodies.get_mut(handle) {
        rb.apply_impulse(vector![ix, iy, iz], true);
    }
    Ok(atoms::ok())
}

/// Steps the world forward by `dt` seconds.
#[rustler::nif]
fn step(res: ResourceArc<WorldRes>, dt: f32) -> Atom {
    res.inner.lock().unwrap().step(dt);
    atoms::ok()
}

/// Reads every body's `{id, {x, y, z}, {qx, qy, qz, qw}}`. Called each
/// frame to drive the scene.
#[rustler::nif]
fn transforms<'a>(env: Env<'a>, res: ResourceArc<WorldRes>) -> Term<'a> {
    let world = res.inner.lock().unwrap();
    let list: Vec<(u32, (f32, f32, f32), (f32, f32, f32, f32))> = world
        .bodies
        .iter()
        .enumerate()
        .filter_map(|(ix, handle)| {
            let rb = world.rigid_bodies.get(*handle)?;
            let t = rb.translation();
            let r = rb.rotation();
            Some((
                ix as u32,
                (t.x, t.y, t.z),
                (r.i, r.j, r.k, r.w),
            ))
        })
        .collect();
    list.encode(env)
}

/// Legacy smoke — kept so MainScreen's mount check doesn't have to
/// change until the demo screen replaces it.
#[rustler::nif]
fn smoke_drop() -> f32 {
    let mut world = World::new();
    world
        .colliders
        .insert(ColliderBuilder::cuboid(50.0, 0.1, 50.0).build());

    let handle = {
        let World {
            rigid_bodies,
            colliders,
            ..
        } = &mut world;

        let h = rigid_bodies.insert(
            RigidBodyBuilder::dynamic()
                .translation(vector![0.0, 5.0, 0.0])
                .build(),
        );
        colliders.insert_with_parent(
            ColliderBuilder::ball(1.0).restitution(0.5).build(),
            h,
            rigid_bodies,
        );
        h
    };

    for _ in 0..120 {
        world.step(1.0 / 60.0);
    }
    world.rigid_bodies[handle].translation().y
}

rustler::init!("Elixir.RapierLab.Physics");
