# 0061. Restart the camera bridges on every enumeration, and decode on the GPU

- Status: Accepted
- Date: 2026-11-04

## Context

Element in Zen showed a blank picture from the OBSBOT Tiny 2 Lite (USB
`3564:fef9`). Zen reads the camera through two `gst-launch` user services,
`obsbot-raw-camera` (1080p) and `obsbot-raw-camera-720p`, which republish the
PipeWire v4l2 node as raw `Video/Source` nodes.

Three separate faults were stacked:

- **Stale bridges.** The camera's USB hub (GenesysLogic `05e3:0610`) drops
  and re-enumerates on its own, with no suspend: five times in one day. The
  bridges kept links to the dead node and showed blank. `Restart=always` only
  fires when the process exits, and these did not. `camera-resume` covered
  only the suspend path, and only restarted `virtual-camera@*`.
- **Software decode.** `jpegdec ! videoscale ! videoconvert` ran on one
  streaming thread. `top -H` showed that thread at 95-100% of a core while 31
  others idled, which gave uneven frames whenever the system got busy.
- **Flicker.** The camera's power line frequency control defaulted to a
  setting that flickers under 50 Hz mains lighting. Setting
  `power_line_frequency=1` live removed it.

## Decision

- **Restart on every enumeration.** `modules/camera-resume.nix` gets
  `restartUserUnits`. A udev rule on the `video4linux` add event (index 0, by
  vendor and product ID) starts `camera-reenumerated.service`. It waits 3 s
  for WirePlumber to publish the node, then runs `systemctl --user
  try-restart` on each listed unit. `try-restart` leaves a stopped bridge
  stopped, so the camera light does not come on unasked.
- **Decode and scale on the GPU.** The bridges use `jpegparse ! vajpegdec !
  vapostproc` with a `queue` either side, from `gst-plugins-bad`. On
  `ali-desktop`, `renderD128` is the RX 9070 XT and the first VA device, so
  `vajpegdec` binds to it. 600 frames of 1080p MJPEG to 720p YUY2 took 3.09 s
  of CPU in software and about 0.8 s on the GPU, at about 127 fps. With Zen
  consuming, the busiest bridge thread sat at 4.7% of a core.
- **Persist the control.** `controls` per device in `camera-resume` sets V4L2
  controls from a udev `RUN` on every add, because UVC controls reset on each
  enumeration. `ali-desktop` sets `power_line_frequency = 1` (50 Hz).

## Alternatives rejected

- **Restart the bridges from `camera-resume` only.** Misses every hub drop
  that is not a suspend, which was most of them.
- **Watch the PipeWire graph for dead links.** More moving parts than reacting
  to the kernel event that causes the fault.
- **Software decode with a bigger buffer.** The cost is CPU on a single
  thread, not buffering.
- **Set the control once at boot.** It resets on the next enumeration.

## Consequences

- The picture recovers by itself within about 3 s of any re-enumeration.
  Element still has to re-pick the camera, since the browser ends the old
  stream.
- The bridges have no software fallback. If VA-API decode breaks (driver
  change, GPU reset, render node reorder), they fail to link and
  `Restart=always` loops. Look for the failed `vajpegdec` link in the unit's
  journal.
- The 3 s wait is fixed. A slow re-enumeration could restart a bridge before
  the node exists; waiting for the node would remove that.
- The cause of the hub drops is unknown (power, cable or xhci). This record
  makes them survivable, not rare.

## Evidence

Verified on `ali-desktop` on 2026-11-04 after the switch:

```text
$ udevadm test --action=add <video2 devpath>
  SYSTEMD_WANTS=camera-reenumerated.service
$ sudo udevadm trigger --action=add /dev/v4l/by-id/usb-Remo_Tech_Co.__Ltd._OBSBOT_Tiny_2_Lite-video-index0
camera-reenumerated: restarting obsbot-raw-camera.service
camera-reenumerated: restarting obsbot-raw-camera-720p.service
```

The picture returned after the trigger. Persisting the control was checked
with the build, not yet across a real enumeration; confirm with
`v4l2-ctl -d /dev/webcam --get-ctrl=power_line_frequency` (expect `1`).

## Revisit when

- The hub drops stop, or their cause is found.
- A restart lands before the node exists: replace the fixed wait with a poll
  for the node.
- VA-API decode proves fragile: add a software fallback pipeline.
