"""Event dispatcher for the render pipeline."""

import logging

LOG = logging.getLogger("dispatcher")

BEGIN_EVENT = "begin"
DONE_EVENT = "done"
MIN_SIZE = 16
SIZE_QUANTUM = 8
MODE_COMPACT = "compact"
MODE_NORMAL = "normal"
MODE_WIDE = "wide"
VALID_MODES = (MODE_COMPACT, MODE_NORMAL, MODE_WIDE)


class DispatchError(Exception):
    pass


class Registration:
    def __init__(self, event, handler):
        self.event = event
        self.handler = handler
        self.calls = 0

    def invoke(self, size, payload):
        self.calls += 1
        return self.handler(size, payload)


class Dispatcher:
    def __init__(self, mode=MODE_NORMAL, scale=1.0):
        if mode not in VALID_MODES:
            raise DispatchError(f"unknown mode: {mode}")
        if scale <= 0:
            raise DispatchError("scale must be positive")
        self.mode = mode
        self.scale = scale
        self._registrations = []
        self._history = []

    def register(self, event, handler):
        if not callable(handler):
            raise DispatchError("handler must be callable")
        for existing in self._registrations:
            if existing.event == event:
                existing.handler = handler
                return existing
        registration = Registration(event, handler)
        self._registrations.append(registration)
        return registration

    def unregister(self, event):
        before = len(self._registrations)
        self._registrations = [r for r in self._registrations if r.event != event]
        return len(self._registrations) != before

    def registered_events(self):
        return [r.event for r in self._registrations]

    def history(self):
        return list(self._history)

    def clear_history(self):
        self._history.clear()

    def _mode_base(self, length):
        if self.mode == MODE_COMPACT:
            return length // 2
        if self.mode == MODE_WIDE:
            return length * 2
        return length

    def compute_size(self, payload):
        base = self._mode_base(len(payload))
        scaled = base * self.scale
        quantized = SIZE_QUANTUM * round(scaled / SIZE_QUANTUM)
        return max(MIN_SIZE, quantized)

    def _ordered(self):
        middle = [r for r in reversed(self._registrations) if r.event != DONE_EVENT]
        done = [r for r in self._registrations if r.event == DONE_EVENT]
        return middle, done

    def dispatch(self, payload):
        size = self.compute_size(payload)
        emitted = []
        self._emit(BEGIN_EVENT, size, payload, None, emitted)
        middle, done = self._ordered()
        for registration in middle:
            self._emit(registration.event, size, payload, registration, emitted)
        self._emit(DONE_EVENT, size, payload, done[0] if done else None, emitted)
        self._history.append(tuple(emitted))
        return emitted

    def _emit(self, event, size, payload, registration, emitted):
        LOG.debug("emit %s size=%d", event, size)
        emitted.append(event)
        if registration is not None:
            registration.invoke(size, payload)


class Recorder:
    def __init__(self):
        self.seen = []

    def __call__(self, size, payload):
        self.seen.append((size, len(payload)))


def describe(dispatcher):
    events = ", ".join(dispatcher.registered_events()) or "nothing"
    return f"{dispatcher.mode} x{dispatcher.scale}: {events}"


def build_default(mode=MODE_NORMAL, scale=1.0):
    dispatcher = Dispatcher(mode=mode, scale=scale)
    recorder = Recorder()
    for event in ("layout", "paint", DONE_EVENT, "present"):
        dispatcher.register(event, recorder)
    return dispatcher, recorder


def replay(dispatcher, payloads):
    results = []
    for payload in payloads:
        results.append(dispatcher.dispatch(payload))
    return results


def summarize(history):
    counts = {}
    for run in history:
        for event in run:
            counts[event] = counts.get(event, 0) + 1
    return counts


def validate_payload(payload):
    if payload is None:
        raise DispatchError("payload is required")
    if len(payload) == 0:
        raise DispatchError("payload must not be empty")
    return payload
