#!/usr/bin/python
# -*- coding: utf-8 -*-
# GNU General Public License v3.0+ (same as Ansible)
"""Manage one line in ~/.ssh/authorized_keys using ansible.module_utils.common.text.converters."""

from __future__ import annotations

import os
import tempfile

from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.common.text.converters import to_native


def _key_sig(line: str) -> tuple[str, str] | None:
    line = line.strip()
    if not line or line.startswith("#"):
        return None
    parts = line.split(None, 2)
    if len(parts) < 2:
        return None
    return parts[0], parts[1]


def _lines_without_sig(lines: list[str], sig: tuple[str, str]) -> list[str]:
    return [ln for ln in lines if _key_sig(ln) != sig]


def main() -> None:
    module = AnsibleModule(
        argument_spec=dict(
            user=dict(type="str", required=True),
            key=dict(type="str", required=True),
            state=dict(type="str", default="present", choices=["present", "absent"]),
        ),
        supports_check_mode=True,
    )

    user = module.params["user"]
    key = module.params["key"].strip()
    state = module.params["state"]

    if not key:
        module.fail_json(msg="key must not be empty")

    try:
        import pwd

        ent = pwd.getpwnam(user)
    except KeyError as exc:
        module.fail_json(msg="User %s does not exist: %s" % (user, to_native(exc)))
    except Exception as exc:
        module.fail_json(msg="Failed to resolve user %s: %s" % (user, to_native(exc)))

    ssh_dir = os.path.join(ent.pw_dir, ".ssh")
    path = os.path.join(ssh_dir, "authorized_keys")

    try:
        os.makedirs(ssh_dir, mode=0o700, exist_ok=True)
        os.chown(ssh_dir, ent.pw_uid, ent.pw_gid)
    except OSError as exc:
        module.fail_json(msg="Failed to ensure %s: %s" % (ssh_dir, to_native(exc)))

    present_sig = _key_sig(key)
    if present_sig is None:
        module.fail_json(msg="key does not look like a valid OpenSSH public key line")

    before: list[str] = []
    if os.path.isfile(path):
        try:
            with open(path, encoding="utf-8") as fh:
                before = [ln.rstrip("\n") for ln in fh.readlines()]
        except OSError as exc:
            module.fail_json(msg="Failed to read %s: %s" % (path, to_native(exc)))

    if state == "absent":
        after = _lines_without_sig(before, present_sig)
        changed = after != before
        if changed and not module.check_mode:
            try:
                _atomic_write(path, after, ent.pw_uid, ent.pw_gid)
            except OSError as exc:
                module.fail_json(msg="Failed to write %s: %s" % (path, to_native(exc)))
        module.exit_json(changed=changed)

    for ln in before:
        if _key_sig(ln) == present_sig:
            module.exit_json(changed=False)

    after = before + [key]
    if not module.check_mode:
        try:
            _atomic_write(path, after, ent.pw_uid, ent.pw_gid)
        except OSError as exc:
            module.fail_json(msg="Failed to write %s: %s" % (path, to_native(exc)))

    module.exit_json(changed=True)


def _atomic_write(path: str, lines: list[str], uid: int, gid: int) -> None:
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(prefix=".authorized_keys.", dir=d, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            for ln in lines:
                fh.write(ln)
                fh.write("\n")
        os.chmod(tmp, 0o600)
        os.chown(tmp, uid, gid)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except OSError:
                pass


if __name__ == "__main__":
    main()
