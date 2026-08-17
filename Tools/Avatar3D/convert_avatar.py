"""
Avaturn GLB + Mixamo FBX  ->  animated USDZ for RealityKit.

Run headless:

    blender -b --python Tools/Avatar3D/convert_avatar.py -- \
        --model  <path to Avaturn model.glb> \
        --anim   <path to Mixamo Walking.fbx> \
        --out    <path to output .usdz>

The two source assets are deliberately NOT committed to this repo (it is
public, the avatar may be a likeness, and Mixamo's licence is restrictive
about redistributing raw animation files). Keep them locally and point this
script at them; only the generated USDZ is version-controlled.

Why a retarget step at all, when the rigs already match:

  Avaturn exports a Mixamo-named skeleton (Hips/Spine/Spine1/Spine2/
  LeftUpLeg/LeftToeBase/...) in T-pose, and Mixamo's rig is the same
  hierarchy with a `mixamorig:` prefix, also in T-pose. Both rigs orient
  every bone along its local +Y. So the hierarchy maps 1:1 by name.

  What does NOT match is proportions — Mixamo's hips sit at 104.3 cm and
  Avaturn's at 98.4 cm, with limb lengths differing by 5-10%. Copying pose
  matrices verbatim would therefore drag the feet off the floor. So this
  transfers each bone's *rotation delta from its own rest pose* (which is
  proportion-independent) and scales only the Hips translation by the hip
  height ratio. That is the correct transfer for two rigs that share a rest
  pose but not a skeleton size.
"""

import bpy
import sys
import argparse
from mathutils import Matrix

MIXAMO_PREFIX = "mixamorig:"
TARGET_FPS = 30


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--model", required=True)
    p.add_argument("--anim", required=True)
    p.add_argument("--out", required=True)
    return p.parse_args(argv)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = TARGET_FPS


def armatures():
    return [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]


def import_character(path):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.context.scene.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    meshes = [o for o in new if o.type == "MESH"]
    print(f"[character] armature={arm.name} bones={len(arm.data.bones)} meshes={len(meshes)}")
    return arm, meshes


def import_animation(path):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(
        filepath=path,
        use_anim=True,
        # Keep the file's own bone orientations. The transfer below works
        # from each rig's own rest pose, so it does not care how Blender
        # rolls the bones — but it does care that they are not silently
        # re-oriented differently between runs.
        automatic_bone_orientation=False,
        ignore_leaf_bones=False,
    )
    new = [o for o in bpy.context.scene.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    for b in arm.pose.bones:
        if b.name.startswith(MIXAMO_PREFIX):
            b.bone.name = b.name[len(MIXAMO_PREFIX):]
    action = arm.animation_data.action if arm.animation_data else None
    print(f"[animation] armature={arm.name} bones={len(arm.data.bones)} action={action.name if action else None}")
    return arm, action


def ordered_bones(arm, names):
    """Parents before children — a bone's world matrix is only meaningful
    once everything above it has already been placed."""
    out = []

    def walk(bone):
        if bone.name in names:
            out.append(bone.name)
        for c in bone.children:
            walk(c)

    for root in [b for b in arm.data.bones if b.parent is None]:
        walk(root)
    return out


def hips_world_track(src_arm, tgt_arm, action, root, start, end):
    """Sample the donor's hip motion in world space, in target proportions.

    Returns per-frame offsets from the hip's own rest position, already
    scaled to the target's build and with forward travel removed.

    Two corrections happen here. The donor is a different size, so raw
    offsets would bob the wrong amount for this body — hence the hip-height
    ratio. And this particular clip is *not* an in-place walk: the root
    advances steadily forward over the cycle. The Figure has to stay
    centred in frame, so the net horizontal drift is removed as a linear
    ramp, which cancels the travel while leaving the side-to-side weight
    shift and the vertical bob untouched.
    """
    src_w = src_arm.matrix_world
    tgt_w = tgt_arm.matrix_world
    src_rest_world = (src_w @ src_arm.data.bones[root].matrix_local).translation
    tgt_rest_world = (tgt_w @ tgt_arm.data.bones[root].matrix_local).translation
    ratio = (tgt_rest_world.z / src_rest_world.z) if src_rest_world.z else 1.0
    print(f"[retarget] hip height donor={src_rest_world.z:.4f}m "
          f"target={tgt_rest_world.z:.4f}m ratio={ratio:.4f}")

    scene = bpy.context.scene
    raw = {}
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        pose_world = (src_w @ src_arm.pose.bones[root].matrix).translation
        raw[frame] = (pose_world - src_rest_world) * ratio

    span = max(1, end - start)
    drift = raw[end] - raw[start]
    travel = (drift.x ** 2 + drift.y ** 2) ** 0.5
    print(f"[retarget] root travel over cycle = {travel:.4f}m -> removed (walk in place)")

    track = {}
    for frame, offset in raw.items():
        t = (frame - start) / span
        corrected = offset.copy()
        corrected.x -= drift.x * t
        corrected.y -= drift.y * t
        track[frame] = corrected
    return track


def retarget(src_arm, tgt_arm, action):
    src_names = {b.name for b in src_arm.data.bones}
    tgt_names = {b.name for b in tgt_arm.data.bones}
    shared = src_names & tgt_names
    order = ordered_bones(tgt_arm, shared)
    print(f"[retarget] {len(order)} shared bones "
          f"(character-only: {sorted(tgt_names - src_names)}, "
          f"animation-only: {len(src_names - tgt_names)} leaf/end bones)")

    root = "Hips"
    if root not in shared:
        raise SystemExit("no Hips bone in common — rigs are not compatible")

    for pb in tgt_arm.pose.bones:
        pb.rotation_mode = "QUATERNION"

    start, end = (int(round(v)) for v in action.frame_range)
    hips = hips_world_track(src_arm, tgt_arm, action, root, start, end)

    # Mixamo repeats the first pose as the last frame so the clip reads as a
    # complete cycle. Keeping both would stall for one frame on every loop,
    # so the duplicate is dropped.
    scene = bpy.context.scene
    if end > start:
        end -= 1
    print(f"[retarget] baking frames {start}..{end}")
    scene.frame_start, scene.frame_end = start, end

    view_layer = bpy.context.view_layer
    src_w = src_arm.matrix_world
    tgt_w = tgt_arm.matrix_world
    tgt_w_inv = tgt_w.inverted()

    # Everything is compared in world space, so the donor being Y-up with a
    # centimetre scale and the character being Z-up in metres stops
    # mattering — the axis and unit conversion falls out of the matrices.
    rest_cache = {
        n: (src_w @ src_arm.data.bones[n].matrix_local,
            tgt_w @ tgt_arm.data.bones[n].matrix_local)
        for n in order
    }

    for frame in range(start, end + 1):
        scene.frame_set(frame)
        for name in order:
            src_rest_world, tgt_rest_world = rest_cache[name]
            src_pose_world = src_w @ src_arm.pose.bones[name].matrix
            tgt_pb = tgt_arm.pose.bones[name]

            # Transfer the rotation *away from rest*, not the absolute
            # orientation. Both rigs rest in a T-pose, so this is exactly
            # the motion, and it stays correct however each importer chose
            # to roll the bones.
            delta = src_pose_world @ src_rest_world.inverted()
            world = delta @ tgt_rest_world
            armature_space = tgt_w_inv @ world
            rotation = armature_space.to_quaternion().to_matrix().to_4x4()

            if name == root:
                location = (tgt_arm.data.bones[root].matrix_local.translation
                            + (tgt_w_inv.to_3x3() @ hips[frame]))
            else:
                # Rotation only. Each skeleton keeps its own bone lengths,
                # which is what stops the size difference between the two
                # rigs from pulling the character apart.
                location = tgt_pb.matrix.translation

            tgt_pb.matrix = Matrix.Translation(location) @ rotation
            view_layer.update()

            tgt_pb.keyframe_insert("rotation_quaternion", frame=frame)
            if name == root:
                tgt_pb.keyframe_insert("location", frame=frame)

    if tgt_arm.animation_data and tgt_arm.animation_data.action:
        tgt_arm.animation_data.action.name = "Walk"
    print(f"[retarget] done — {end - start + 1} frames @ {TARGET_FPS}fps "
          f"= {(end - start + 1) / TARGET_FPS:.4f}s loop")


def export_usdz(path):
    bpy.ops.wm.usd_export(
        filepath=path,
        export_animation=True,
        export_armatures=True,
        export_materials=True,
        export_textures=True,
        export_meshes=True,
        export_normals=True,
        export_uvmaps=True,
        generate_preview_surface=True,
        export_cameras=False,
        export_lights=False,
        # Avaturn ships ~60 ARKit facial blend shapes. Nothing in this
        # prototype drives a face, so they would only bake an all-zero
        # weight track for every frame and carry their geometry deltas
        # along for the ride — most of the asset size for no visible
        # result. Re-enable when facial animation is actually on the table.
        export_shapekeys=False,
        only_deform_bones=False,
        use_instancing=False,
        evaluation_mode="RENDER",
        # Blender is Z-up / -Y forward; USD and RealityKit expect Y-up /
        # -Z forward. Without this the avatar arrives lying on its back.
        convert_orientation=True,
        export_global_up_selection="Y",
        export_global_forward_selection="NEGATIVE_Z",
        root_prim_path="/Root",
    )
    print(f"[export] wrote {path}")


def main():
    args = parse_args()
    reset_scene()
    tgt_arm, _ = import_character(args.model)
    src_arm, action = import_animation(args.anim)
    if action is None:
        raise SystemExit("animation file contained no action")
    retarget(src_arm, tgt_arm, action)

    # The donor rig must not ship inside the runtime asset.
    bpy.data.objects.remove(src_arm, do_unlink=True)

    export_usdz(args.out)


main()
