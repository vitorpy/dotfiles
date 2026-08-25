import QtQuick
import QtTest
import "../private_dot_config/quickshell/berg/AudioRoute.js" as AudioRoute

TestCase {
    name: "AudioRoute"

    function serialized(sinks) {
        return JSON.stringify(sinks);
    }

    function test_speakerRouteWinsOverConnectedHeadphones() {
        const sinks = [{
            name: "internal",
            active_port: "analog-output-speaker",
            ports: [{
                name: "analog-output-headphones",
                type: "Headphones",
                availability: "available"
            }]
        }];

        verify(!AudioRoute.activeSinkUsesHeadphones(serialized(sinks), "internal"));
    }

    function test_wiredHeadphonesRoute() {
        const sinks = [{
            name: "internal",
            active_port: "analog-output-headphones"
        }];

        verify(AudioRoute.activeSinkUsesHeadphones(serialized(sinks), "internal"));
    }

    function test_bluetoothHeadsetMetadata() {
        const sinks = [{
            name: "bluez_output.example",
            properties: {
                "device.icon_name": "audio-headset-bluetooth",
                "api.bluez5.address": "44:73:d6:ca:87:f8"
            }
        }];

        const info = AudioRoute.activeSinkInfo(serialized(sinks), "bluez_output.example");
        verify(info.headphonesActive);
        compare(info.bluetoothAddress, "44:73:D6:CA:87:F8");
    }

    function test_usbHeadphoneFormFactor() {
        const sinks = [{
            name: "usb-output",
            properties: {
                "device.form_factor": "headphones"
            }
        }];

        verify(AudioRoute.activeSinkUsesHeadphones(serialized(sinks), "usb-output"));
    }

    function test_onlyClassifiesTheDefaultSink() {
        const sinks = [{
            name: "bluetooth-headset",
            properties: {
                "device.icon_name": "audio-headset-bluetooth",
                "api.bluez5.address": "44:73:D6:CA:87:F8"
            }
        }, {
            name: "internal",
            active_port: "analog-output-speaker"
        }];

        const info = AudioRoute.activeSinkInfo(serialized(sinks), "internal");
        verify(!info.headphonesActive);
        compare(info.bluetoothAddress, "");
    }

    function test_unknownSinkUsesSpeakerFallback() {
        verify(!AudioRoute.activeSinkUsesHeadphones(serialized([]), "missing"));
    }

    function test_malformedDataIsRejected() {
        let rejected = false;
        try {
            AudioRoute.activeSinkUsesHeadphones("not json", "internal");
        } catch (error) {
            rejected = true;
        }
        verify(rejected);
    }
}
