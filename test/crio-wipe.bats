#!/usr/bin/env bats

# this test suite tests crio wipe running with combinations of cri-o and
# podman.

load helpers
PODMAN_BINARY=${PODMAN_BINARY:-$(command -v podman || true)}

function setup() {
	setup_test
	export CONTAINER_VERSION_FILE="$TESTDIR"/version.tmp
	export CONTAINER_VERSION_FILE_PERSIST="$TESTDIR"/version-persist.tmp
}

function run_podman_with_args() {
	if [ -n "$PODMAN_BINARY" ]; then
		"$PODMAN_BINARY" --root "$TESTDIR/crio" --runroot "$TESTDIR/crio-run" "$@"
	fi
}

function teardown() {
	cleanup_test
	run_podman_with_args stop -a
	run_podman_with_args rm -fa
}

# run crio_wipe calls crio_wipe and tests it succeeded
function run_crio_wipe() {
	"$CRIO_BINARY_PATH" --config "$CRIO_CONFIG" wipe
}

# test_crio_wiped_containers checks if a running crio instance
# has no containers or pods
function test_crio_wiped_containers() {
	output=$(crictl pods -v)
	[ "$output" == "" ]
	output=$(crictl ps -v)
	[ "$output" == "" ]
}

function test_crio_did_not_wipe_containers() {
	output=$(crictl pods -v)
	[ "$output" != "" ]
}

function test_crio_wiped_images() {
	# check that the pause image was removed, as we removed a pod
	# that used it
	output=$(crictl images)
	[[ ! "$output" == *"pause"* ]]
}

function test_crio_did_not_wipe_images() {
	# check that the pause image was not removed
	output=$(crictl images)
	[[ "$output" == *"pause"* ]]
}

function start_crio_with_stopped_pod() {
	start_crio

	local pod_id
	pod_id=$(crictl runp "$TESTDATA"/sandbox_config.json)
	crictl stopp "$pod_id"
}

@test "remove containers and images when remove both" {
	start_crio_with_stopped_pod
	stop_crio_no_clean

	rm "$CONTAINER_VERSION_FILE"
	rm "$CONTAINER_VERSION_FILE_PERSIST"
	run_crio_wipe

	start_crio_no_setup
	test_crio_wiped_containers
	test_crio_wiped_images
}

@test "remove containers when remove temporary" {
	start_crio_with_stopped_pod
	stop_crio_no_clean

	rm "$CONTAINER_VERSION_FILE"
	run_crio_wipe

	start_crio_no_setup
	test_crio_wiped_containers
	test_crio_did_not_wipe_images
}

@test "clear neither when remove persist" {
	start_crio_with_stopped_pod
	stop_crio_no_clean

	rm "$CONTAINER_VERSION_FILE_PERSIST"
	run_crio_wipe

	start_crio_no_setup
	test_crio_did_not_wipe_containers
	test_crio_did_not_wipe_images
}

@test "don't clear podman containers" {
	if [ -z "$PODMAN_BINARY" ]; then
		skip "Podman not installed"
	fi

	start_crio_with_stopped_pod
	stop_crio_no_clean

	run_podman_with_args run --name test -d quay.io/crio/busybox:latest top

	run_crio_wipe

	run_podman_with_args ps -a | grep test
}
