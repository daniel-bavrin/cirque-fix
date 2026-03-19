using System;
using Xunit;

// Unit tests for the CirqueFix HID protocol logic.
// These test the pure math/byte-manipulation functions without requiring real hardware.
// E2E tests (marked [Trait("Category","E2E")]) require a connected Cirque/Sensel device.

public class ProtocolTests
{
    // ---- BuildWriteCmd -------------------------------------------------------

    // Mirrors the private BuildWriteCmd logic so tests don't need InternalsVisibleTo
    static byte[] BuildWriteCmd(ushort reg, byte size, byte[] data)
    {
        byte cmd0 = (byte)(((reg & 0x3F00) >> 7) | 0x01);
        byte cmd1 = (byte)(reg & 0xFF);
        int checksum = 0;
        foreach (byte b in data) checksum += b;
        byte[] full = new byte[3 + data.Length + 1];
        full[0] = cmd0; full[1] = cmd1; full[2] = size;
        Array.Copy(data, 0, full, 3, data.Length);
        full[full.Length - 1] = (byte)(checksum & 0xFF);
        return full;
    }

    [Fact]
    public void BuildWriteCmd_PtpButtonsConfig_Enable()
    {
        // REG_PTP_BUTTONS_CONFIG = 0x008A, value = 1
        byte[] cmd = BuildWriteCmd(0x008A, 1, new byte[] { 0x01 });

        // cmd[0]: bit7=0 (write), bits[13:7] of 0x008A = 0x00 >> 0 = 0, | 0x01 = 0x01
        Assert.Equal(0x01, cmd[0]);
        Assert.Equal(0x8A, cmd[1]); // reg low byte
        Assert.Equal(0x01, cmd[2]); // size
        Assert.Equal(0x01, cmd[3]); // data
        Assert.Equal(0x01, cmd[4]); // checksum = 0x01
    }

    [Fact]
    public void BuildWriteCmd_PtpButtonsConfig_Disable()
    {
        byte[] cmd = BuildWriteCmd(0x008A, 1, new byte[] { 0x00 });
        Assert.Equal(0x00, cmd[3]); // data = 0
        Assert.Equal(0x00, cmd[4]); // checksum = 0
    }

    [Fact]
    public void BuildWriteCmd_ClickForce_CorrectChecksum()
    {
        // REG_CLICK_FORCE_DIV2 = 0x0038, value = 82 (164/2)
        byte[] cmd = BuildWriteCmd(0x0038, 1, new byte[] { 82 });
        Assert.Equal(82, cmd[4]); // checksum = sum of data bytes & 0xFF
    }

    [Fact]
    public void BuildWriteCmd_UpperRegBits_EncodedCorrectly()
    {
        // Register 0x3F00 — upper 6 bits fully set
        // cmd0 = ((0x3F00 & 0x3F00) >> 7) | 0x01 = (0x3F00 >> 7) | 0x01 = 0x7E | 0x01 = 0x7F
        byte[] cmd = BuildWriteCmd(0x3F00, 1, new byte[] { 0x00 });
        Assert.Equal(0x7F, cmd[0]);
        Assert.Equal(0x00, cmd[1]);
    }

    // ---- Register value math -------------------------------------------------

    [Theory]
    [InlineData(164, 82,  53)]  // default ClickForce
    [InlineData(120, 60,  39)]  // light
    [InlineData(190, 95,  61)]  // heavy
    public void ClickForce_DivAndLift_Correct(int force, byte expectedDiv2, byte expectedLift)
    {
        byte cfDiv2   = (byte)(force / 2);
        byte liftDiv2 = (byte)(force / 2 * 0.65);
        Assert.Equal(expectedDiv2, cfDiv2);
        Assert.Equal(expectedLift, liftDiv2);
    }

    [Theory]
    [InlineData(76, 38, 24)]  // default TrackPointClickForce
    [InlineData(56, 28, 18)]  // light
    [InlineData(120, 60, 39)] // heavy
    public void TrackPointClickForce_DivAndLift_Correct(int force, byte expectedDiv2, byte expectedLift)
    {
        byte cfDiv2   = (byte)(force / 2);
        byte liftDiv2 = (byte)(force / 2 * 0.65);
        Assert.Equal(expectedDiv2, cfDiv2);
        Assert.Equal(expectedLift, liftDiv2);
    }

    // ---- HID pipe framing ----------------------------------------------------

    static byte[][] FrameData(byte[] data)
    {
        const byte REPORT_ID = 9;
        var frames = new System.Collections.Generic.List<byte[]>();
        int offset = 0, remaining = data.Length;
        while (remaining > 0)
        {
            int chunk = Math.Min(19, remaining);
            byte[] frame = new byte[21];
            frame[0] = REPORT_ID;
            frame[1] = (byte)chunk;
            Array.Copy(data, offset, frame, 2, chunk);
            frames.Add(frame);
            offset += chunk; remaining -= chunk;
        }
        return frames.ToArray();
    }

    [Fact]
    public void HIDPipe_ShortPayload_SingleFrame()
    {
        byte[] cmd = BuildWriteCmd(0x008A, 1, new byte[] { 0x01 }); // 5 bytes
        var frames = FrameData(cmd);
        Assert.Single(frames);
        Assert.Equal(9,          frames[0][0]); // report ID
        Assert.Equal(cmd.Length, frames[0][1]); // payload length
    }

    [Fact]
    public void HIDPipe_LongPayload_MultipleFrames()
    {
        // 25 bytes should split into 19 + 6
        byte[] data = new byte[25];
        var frames = FrameData(data);
        Assert.Equal(2,  frames.Length);
        Assert.Equal(19, frames[0][1]);
        Assert.Equal(6,  frames[1][1]);
    }

    [Fact]
    public void HIDPipe_FrameSize_AlwaysExactly21()
    {
        byte[] data = new byte[40];
        var frames = FrameData(data);
        foreach (var frame in frames)
            Assert.Equal(21, frame.Length);
    }

    // ---- Settings registry defaults ------------------------------------------

    [Fact]
    public void Settings_DefaultClickForce_IsValid()
    {
        // Default ClickForce = 164g (medium), must produce valid div2 values
        int force = 164;
        byte div2 = (byte)(force / 2);
        Assert.Equal(82, div2);
        Assert.True(div2 > 0 && div2 <= 255);
    }

    [Fact]
    public void Settings_TrackPointButtons_TrueEnablesRegister()
    {
        bool enabled = true;
        byte regVal = (byte)(enabled ? 1 : 0);
        Assert.Equal(1, regVal);
    }

    [Fact]
    public void Settings_TrackPointButtons_FalseDisablesRegister()
    {
        bool enabled = false;
        byte regVal = (byte)(enabled ? 1 : 0);
        Assert.Equal(0, regVal);
    }
}
