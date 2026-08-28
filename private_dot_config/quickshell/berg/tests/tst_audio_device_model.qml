import QtQuick
import QtTest
import "../AudioDeviceModel.js" as AudioDeviceModel

TestCase {
    name: "AudioDeviceModel"

    function node(id, name, description, mediaClass, isSink, isStream, extraProperties) {
        const properties = Object.assign({ "media.class": mediaClass }, extraProperties || {});
        return {
            id: id,
            name: name,
            description: description,
            nickname: "",
            properties: properties,
            isSink: isSink,
            isStream: isStream,
            audio: {}
        };
    }

    function test_filtersPhysicalAudioNodes() {
        const sink = node(1, "sink", "Speakers", "Audio/Sink", true, false);
        const source = node(2, "source", "Microphone", "Audio/Source", false, false);
        const playback = node(3, "stream", "Browser", "Stream/Output/Audio", true, true);
        const camera = node(4, "camera", "Camera", "Video/Source", false, false);
        camera.audio = null;

        compare(AudioDeviceModel.snapshot([sink, source, playback, camera], "sink", sink).length, 1);
        compare(AudioDeviceModel.snapshot([sink, source, playback, camera], "source", source).length, 1);
    }

    function test_jabraIsFirstPreferenceForBothDirections() {
        const speakers = node(1, "speakers", "Laptop speakers", "Audio/Sink", true, false);
        const jabraOutput = node(2, "jabra-output", "Jabra Evolve", "Audio/Sink", true, false);
        const internalMic = node(3, "internal-mic", "Internal microphone", "Audio/Source", false, false);
        const jabraMic = node(
            4,
            "usb-source",
            "Headset microphone",
            "Audio/Source",
            false,
            false,
            { "device.vendor.name": "GN Netcom A/S" }
        );

        const sinks = AudioDeviceModel.snapshot([speakers, jabraOutput], "sink", speakers);
        const sources = AudioDeviceModel.snapshot([internalMic, jabraMic], "source", internalMic);

        compare(sinks[0].name, "jabra-output");
        verify(sinks[0].jabra);
        compare(sources[0].name, "usb-source");
        verify(sources[0].jabra);
    }

    function test_activeDevicePrecedesOtherNonJabraDevices() {
        const first = node(1, "first", "Alpha", "Audio/Sink", true, false);
        const active = node(2, "active", "Zulu", "Audio/Sink", true, false);
        const devices = AudioDeviceModel.snapshot([first, active], "sink", active);

        compare(devices[0].name, "active");
        verify(devices[0].active);
    }

    function test_deduplicatesNodeNames() {
        const first = node(1, "same", "First", "Audio/Sink", true, false);
        const duplicate = node(2, "same", "Duplicate", "Audio/Sink", true, false);
        compare(AudioDeviceModel.snapshot([first, duplicate], "sink", null).length, 1);
    }

    function test_acceptsQmlListLikeValues() {
        const sink = node(1, "sink", "Speakers", "Audio/Sink", true, false);
        const listLike = { 0: sink, length: 1 };
        const devices = AudioDeviceModel.snapshot(listLike, "sink", sink);

        compare(devices.length, 1);
        compare(devices[0].name, "sink");
    }
}
