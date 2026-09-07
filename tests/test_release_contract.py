from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMMIT = "29112bef099274229cadff79cdff7bf7b99c4b77"


def test_021_inputs_and_signed_tur_python_are_aligned() -> None:
    manifest = json.loads((ROOT / "manifest/wheels.json").read_text("utf-8"))
    lock = json.loads((ROOT / "audit/upstream-lock.json").read_text("utf-8"))
    package_workflow = (ROOT / ".github/workflows/build-hermes-package.yml").read_text("utf-8")
    assert manifest["hermes"] == {
        "profile": "termux",
        "python": "3.13.13",
        "ref": COMMIT,
        "repository": "https://github.com/NousResearch/hermes-agent.git",
    }
    assert lock["hermes"]["commit"] == COMMIT
    assert lock["hermes"]["release"] == "v2026.8.31"
    assert lock["hermes"]["version"] == "0.21.0"
    assert lock["artifacts"]["audit/resolved.txt"]["entries"] == 75
    assert manifest["python_distribution"]["retrieval"] == "signed-apt"
    assert manifest["python_distribution"]["package"] == "python3.13"
    assert manifest["python_distribution"]["version"] == "3.13.13"
    assert "url" not in manifest["python_distribution"]
    assert manifest["python_distribution"]["sha256"] == (
        "f1b37543613eb40afeaaeaf25056bf1d2a7ed851e6f27a25213667cb66545e69"
    )
    assert f"default: {COMMIT}" in package_workflow
    assert "default: 0.21.0+termux1" in package_workflow


def test_workflows_derive_wheel_count_and_route_to_current_repository() -> None:
    wheel_workflow = (ROOT / ".github/workflows/build-wheelhouse.yml").read_text("utf-8")
    package_workflow = (ROOT / ".github/workflows/build-hermes-package.yml").read_text("utf-8")
    build_script = (ROOT / "scripts/build_hermes_deb_termux.sh").read_text("utf-8")
    assert 'len(json.load(open("manifest/wheels.json"))["packages"])' in wheel_workflow
    assert 'len(json.load(open(sys.argv[1]))["packages"])' in build_script
    assert '--repo "$GITHUB_REPOSITORY"' in package_workflow
    assert '-e HERMES_WHEELHOUSE_REPOSITORY=' not in package_workflow
    assert '"$WHEELHOUSE_TAG" "$WHEELHOUSE_SUMS_SHA256" "$GITHUB_REPOSITORY"' in package_workflow
    assert 'WHEELHOUSE_REPOSITORY="${7:?wheelhouse repository is required}"' in build_script
    assert "adybag14-cyber/termux-hermes" not in package_workflow


def test_package_build_is_locked_binary_only_and_metadata_is_dynamic() -> None:
    script = (ROOT / "scripts/build_hermes_deb_termux.sh").read_text("utf-8")
    workflow = (ROOT / ".github/workflows/build-hermes-package.yml").read_text("utf-8")
    assert '--requirements "$PACKAGING_ROOT/audit/resolved.txt"' in script
    assert '--constraint "$PACKAGING_ROOT/audit/lock-constraints.txt"' in script
    assert "--only-binary :all:" in script
    assert 'uv pip install --python "$VENV_PY" --no-deps "$APP"' in script
    assert "--editable" not in script
    assert "nemo-relay" in script
    assert 'test "$HERMES_VERSION" = "${PACKAGE_VERSION%%+*}"' in script
    assert 'data["hermes_version"] == "$PACKAGE_VERSION".split("+", 1)[0]' in workflow
    assert 'assert data["hermes_version"] == "0.20.6"' not in workflow


def test_clean_container_smoke_pins_tur_python_31313() -> None:
    workflow = (ROOT / ".github/workflows/build-hermes-package.yml").read_text("utf-8")
    assert "Clean Termux smoke against signed TUR Python 3.13.13" in workflow
    assert "python3.13_3.13.13_aarch64.deb" in workflow
    assert "platform.python_version())\")\" = 3.13.13" in workflow


def test_new_build_paths_use_signed_apt_not_contributor_or_raw_pool() -> None:
    paths = (
        ROOT / "scripts/termux_build.sh",
        ROOT / "scripts/build_hermes_deb_termux.sh",
        ROOT / ".github/workflows/build-hermes-package.yml",
    )
    for path in paths:
        text = path.read_text("utf-8")
        assert "tur-repo" in text
        assert "apt-get download python3.13=3.13.13" in text
        assert "f1b37543613eb40afeaaeaf25056bf1d2a7ed851e6f27a25213667cb66545e69" in text
        assert "adybag14-cyber/termux-python" not in text
        assert "tur.kcubeterm.com/pool" not in text


def test_anydoc_native_extension_is_in_manifest_and_runtime_smokes() -> None:
    manifest = json.loads((ROOT / "manifest/wheels.json").read_text("utf-8"))
    package = next(item for item in manifest["packages"] if item["name"] == "firecrawl-anydoc")
    assert package["imports"] == ["anydoc", "anydoc._anydoc"]
    package_script = (ROOT / "scripts/build_hermes_deb_termux.sh").read_text("utf-8")
    workflow = (ROOT / ".github/workflows/build-hermes-package.yml").read_text("utf-8")
    assert 'package["imports"]' in package_script
    assert workflow.count('importlib.import_module("anydoc._anydoc")') >= 1