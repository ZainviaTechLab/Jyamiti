import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' as ffi2;
import 'package:win32/win32.dart' as win32;

// ─── Windows Job Object: kill-on-close safety net for spawned ffmpeg
// processes ──────────────────────────────────────────────────────────────
// `Process.start` on Windows does not tie a child process's lifetime to
// this app's -- if `jyamiti.exe` is hard-killed (Task Manager "End Task",
// a crash, a forced restart) instead of exiting normally, any ffmpeg child
// still running keeps right on running as an orphan. That matters most for
// `_cameraProcess`: it holds an exclusive DirectShow handle on the webcam
// for as long as it's alive, so an orphaned copy leaves the webcam locked
// system-wide -- unusable in any other app -- until it's manually killed
// in Task Manager or the machine reboots.
//
// A Windows Job Object created with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`
// fixes this at the OS level: every process assigned to it is
// automatically terminated the instant the job's last handle closes --
// which Windows itself does when this process exits, for ANY reason,
// crash included, with no Dart code needing to run for it to take effect.
// `package:win32` wraps the handful of plain functions this needs
// (`CreateJobObject`/`SetInformationJobObject`/`AssignProcessToJobObject`)
// but not the specific limit-information struct or constant, so those are
// defined here directly via `dart:ffi`, matching the real Win32 struct
// layout (`JOBOBJECT_EXTENDED_LIMIT_INFORMATION`) field-for-field.
//
// Extracted into its own file, imported conditionally (see
// job_object_lifetime.dart), because `ffi.Struct` subclasses with
// `external` fields -- like the three below -- don't compile for web at
// all (a hard dart2js/dart2wasm restriction: "Only JS interop members may
// be 'external'"), independent of whether they're ever instantiated at
// runtime. Keeping mathpad_recording_service.dart itself free of any
// dart:ffi/win32 import is what lets it (and everything that imports it,
// including main.dart) compile for web.

const int _kJobObjectExtendedLimitInformation = 9;
const int _kJobObjectLimitKillOnJobClose = 0x00002000;
const int _kProcessSetQuota = 0x0100;
const int _kProcessTerminate = 0x0001;

base class _IoCounters extends ffi.Struct {
  @ffi.Uint64()
  external int readOperationCount;
  @ffi.Uint64()
  external int writeOperationCount;
  @ffi.Uint64()
  external int otherOperationCount;
  @ffi.Uint64()
  external int readTransferCount;
  @ffi.Uint64()
  external int writeTransferCount;
  @ffi.Uint64()
  external int otherTransferCount;
}

base class _JobObjectBasicLimitInformation extends ffi.Struct {
  @ffi.Int64()
  external int perProcessUserTimeLimit;
  @ffi.Int64()
  external int perJobUserTimeLimit;
  @ffi.Uint32()
  external int limitFlags;
  @ffi.Uint64()
  external int minimumWorkingSetSize;
  @ffi.Uint64()
  external int maximumWorkingSetSize;
  @ffi.Uint32()
  external int activeProcessLimit;
  @ffi.Uint64()
  external int affinity;
  @ffi.Uint32()
  external int priorityClass;
  @ffi.Uint32()
  external int schedulingClass;
}

base class _JobObjectExtendedLimitInformation extends ffi.Struct {
  external _JobObjectBasicLimitInformation basicLimitInformation;
  external _IoCounters ioInfo;
  @ffi.Uint64()
  external int processMemoryLimit;
  @ffi.Uint64()
  external int jobMemoryLimit;
  @ffi.Uint64()
  external int peakProcessMemoryUsed;
  @ffi.Uint64()
  external int peakJobMemoryUsed;
}

/// Created lazily, once per app run -- every process ever assigned to it
/// (see `tieProcessLifetimeToApp`) dies the moment this handle closes,
/// which Windows does automatically on process exit for any reason.
int? _killOnCloseJobHandle;

/// Best-effort and silent on any failure (never throws) -- a spawned
/// ffmpeg process working normally matters far more than this safety net
/// existing at all, so nothing here is allowed to affect the actual
/// recording if the OS call fails for some unexpected reason.
int? _ensureKillOnCloseJob() {
  if (_killOnCloseJobHandle != null) return _killOnCloseJobHandle;
  if (!Platform.isWindows) return null;
  try {
    final int job = win32.CreateJobObject(ffi.nullptr, ffi.nullptr);
    if (job == 0) return null;

    final ffi.Pointer<_JobObjectExtendedLimitInformation> info =
        ffi2.calloc<_JobObjectExtendedLimitInformation>();
    try {
      info.ref.basicLimitInformation.limitFlags =
          _kJobObjectLimitKillOnJobClose;
      final int ok = win32.SetInformationJobObject(
        job,
        _kJobObjectExtendedLimitInformation,
        info.cast(),
        ffi.sizeOf<_JobObjectExtendedLimitInformation>(),
      );
      if (ok == 0) {
        win32.CloseHandle(job);
        return null;
      }
    } finally {
      ffi2.calloc.free(info);
    }

    _killOnCloseJobHandle = job;
    return job;
  } catch (_) {
    return null;
  }
}

/// Assigns the OS process with [pid] to the kill-on-close job so it's
/// terminated automatically if this app's process ever is, gracefully or
/// not -- called right after every ffmpeg `Process.start` in
/// mathpad_recording_service.dart. A no-op on any non-Windows platform
/// (see job_object_lifetime_web.dart for the web variant specifically).
void tieProcessLifetimeToApp(int pid) {
  if (!Platform.isWindows) return;
  try {
    final int? job = _ensureKillOnCloseJob();
    if (job == null) return;
    final int handle = win32.OpenProcess(
      _kProcessSetQuota | _kProcessTerminate,
      0,
      pid,
    );
    if (handle == 0) return;
    win32.AssignProcessToJobObject(job, handle);
    win32.CloseHandle(handle);
  } catch (_) {
    // Un-assigned just falls back to today's behaviour (graceful stop /
    // `dispose()`'s hard kill on a clean exit) -- never worth surfacing.
  }
}
