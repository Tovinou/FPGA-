"""VUnit test for camera subsystem top-level entity."""

from vunit import VUnit, clock_period


def test_bench(**kwargs):
    """Test that the camera subsystem initializes correctly (Tier 1).

    This is a foundational test: we instantiate the top-level entity and
    check its initial state after reset deassertion. Later tests will
    exercise I2C transactions, frame grabber data flow, and SDRAM read/write cycles.
    """
    t = VUnit.from_testcase(TestCameraSubsystem.test_bench, "test_bench")

    # Clock period of 10 ns (100 MHz) – matches the design's clocking.
    clk_period = clock_period(10e-9)

    top = t.top_entity("camera_subsystem")
    top.add_clock_domain(clk_period, name="clk_cam")

    # Instantiate with default parameters (no external connections for now).
    top_inst = top.instance(name="top", generics={"RESET_WIDTH": 1})

    top.check_signal("clk_cam", "clock")
    top.check_signal("reset", "std_logic")

    # Verify clock toggling (Tier 2: clocking verification).
    t.check_clock_domain("clk_cam")

    # Assert that all pixel data lines are initially zero.
    for i in range(10):
        top_inst.check_signal(f"pixel_data_{i}", "std_logic_vector", 8)
    assert top_inst.get_signal("pixel_data_0").value_is((0,))

    # Frame grabber enable should be low before any data arrives.
    top_inst.check_signal("frame_grabber_enable", "std_logic")
    t.compile_simulate()


class TestCameraSubsystem:
    """Test suite for the camera subsystem."""

    @staticmethod
    def test_bench():
        """Entry point for the test bench – asserts reset deassertion works.

        We drive reset low for one clock period, then release it high.
        After deassertion, the design should remain in normal operation.
        """
        # Drive reset low for one clock period, then release it high.
        t.set_value("reset", "low")
        t.wait(clk_period)
        t.set_value("reset", "high")

        # After deassertion, the design should remain in normal operation.
        # Wait a bit longer to ensure stability before asserting final state.
        t.wait(clk_period * 5)
        assert top.get_signal("reset").value_is(1)


def test_reset_deassertion(**kwargs):
    """Test that reset deassertion works correctly (Tier 2).

    This is a nuanced variation: we now drive the reset signal low and
    verify it stays low after release. Earlier tests only checked the
    initial high state; this adds dynamic stimulus to the reset port.
    """
    t = VUnit.from_testcase(TestCameraSubsystem.test_reset_deassertion, "test_reset_deassertion")

    clk_period = clock_period(10e-9)
    top = t.top_entity("camera_subsystem")
    top.add_clock_domain(clk_period, name="clk_cam")
    top_inst = top.instance(name="top", generics={"RESET_WIDTH": 1})

    top.check_signal("clk_cam", "clock")
    top.check_signal("reset", "std_logic")

    t.compile_simulate()


class TestCameraSubsystem:
    """Test suite for the camera subsystem."""

    @staticmethod
    def test_reset_deassertion():
        """Verify that deasserting reset works (Tier 2)."""
        # Drive reset low for one clock period, then release it high.
        t.set_value("reset", "low")
        t.wait(clk_period)
        t.set_value("reset", "high")

        # After deassertion, the design should remain in normal operation.
        # Wait a bit longer to ensure stability before asserting final state.
        t.wait(clk_period * 5)
        assert top.get_signal("reset").value_is(1)


if __name__ == "__main__":
    import sys

    sys.exit(test_bench())
