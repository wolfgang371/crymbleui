require "../spec_helper"
require "../../src/layout/hstack"
require "../../src/layout/vstack"
require "../../src/widgets/expanded"
require "../../src/dsl/builder"

# Tests for Expanded widget and HStack/VStack flex layout

describe "Expanded widget" do
  describe "basic behavior" do
    it "returns child's intrinsic size from measure" do
      expanded = CrymbleUI::Expanded.new
      child = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
      expanded.add_child(child)

      constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800.0, 600.0))
      size = expanded.measure(constraints)

      size.width.should eq(100.0)
      size.height.should eq(50.0)
    end

    it "fills allocated space in perform_layout" do
      expanded = CrymbleUI::Expanded.new
      child = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
      expanded.add_child(child)

      # Parent gives tight constraints (300x200)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 200.0))
      expanded.layout(constraints, CrymbleUI::Vec2.new(10.0, 20.0))

      # Expanded should fill the allocated space
      expanded.bounds.x.should eq(10.0)
      expanded.bounds.y.should eq(20.0)
      expanded.bounds.width.should eq(300.0)
      expanded.bounds.height.should eq(200.0)
    end

    it "returns zero size when no children" do
      expanded = CrymbleUI::Expanded.new
      constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800.0, 600.0))
      size = expanded.measure(constraints)

      size.width.should eq(0.0)
      size.height.should eq(0.0)
    end
  end
end

describe "HStack with Expanded" do
  describe "single expanded child" do
    it "expanded child fills remaining width" do
      hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

      # Fixed child: 100px
      fixed = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
      hstack.add_child(fixed)

      # Expanded child: should fill remaining 700px
      expanded = CrymbleUI::Expanded.new
      exp_child = TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0))
      expanded.add_child(exp_child)
      hstack.add_child(expanded)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      hstack.layout(constraints, CrymbleUI::Vec2.zero)

      # HStack should use full constraint width
      hstack.bounds.width.should eq(800.0)

      # Fixed child at x=0, width=100
      fixed.bounds.x.should eq(0.0)
      fixed.bounds.width.should eq(100.0)

      # Expanded child at x=100, width=700 (remaining space)
      expanded.bounds.x.should eq(100.0)
      expanded.bounds.width.should eq(700.0)
    end
  end

  describe "multiple expanded children" do
    it "splits remaining space equally between two expanded children" do
      hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

      # Fixed child: 200px
      fixed = TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 50.0))
      hstack.add_child(fixed)

      # Two expanded children should each get 300px (600 / 2)
      exp1 = CrymbleUI::Expanded.new
      exp1.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0)))
      hstack.add_child(exp1)

      exp2 = CrymbleUI::Expanded.new
      exp2.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0)))
      hstack.add_child(exp2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      hstack.layout(constraints, CrymbleUI::Vec2.zero)

      # Fixed: x=0, width=200
      fixed.bounds.width.should eq(200.0)

      # exp1: x=200, width=300
      exp1.bounds.x.should eq(200.0)
      exp1.bounds.width.should eq(300.0)

      # exp2: x=500, width=300
      exp2.bounds.x.should eq(500.0)
      exp2.bounds.width.should eq(300.0)
    end
  end

  describe "with spacing" do
    it "accounts for spacing in remaining space calculation" do
      hstack = CrymbleUI::HStack.new(spacing: 10.0, padding: 0.0)

      # Fixed child: 100px
      fixed = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
      hstack.add_child(fixed)

      # Expanded: should get 800 - 100 - 10 (spacing) = 690px
      expanded = CrymbleUI::Expanded.new
      expanded.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0)))
      hstack.add_child(expanded)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      hstack.layout(constraints, CrymbleUI::Vec2.zero)

      # Fixed at x=0
      fixed.bounds.x.should eq(0.0)

      # Expanded at x=110 (100 + 10 spacing), width=690
      expanded.bounds.x.should eq(110.0)
      expanded.bounds.width.should eq(690.0)
    end
  end

  describe "with padding" do
    it "accounts for padding in remaining space calculation" do
      hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 20.0)

      # Expanded: should get 800 - 40 (padding both sides) = 760px
      expanded = CrymbleUI::Expanded.new
      expanded.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0)))
      hstack.add_child(expanded)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      hstack.layout(constraints, CrymbleUI::Vec2.zero)

      # Expanded at x=20 (padding), width=760
      expanded.bounds.x.should eq(20.0)
      expanded.bounds.width.should eq(760.0)
    end
  end

  describe "backward compatibility" do
    it "behaves unchanged when no expanded children (loose constraints)" do
      hstack = CrymbleUI::HStack.new(spacing: 10.0, padding: 0.0)

      child1 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
      child2 = TestWidget.new(measured_size: CrymbleUI::Size.new(150.0, 60.0))
      hstack.add_child(child1)
      hstack.add_child(child2)

      # Use loose constraints (like original tests) - HStack uses intrinsic size
      constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800.0, 600.0))
      hstack.layout(constraints, CrymbleUI::Vec2.zero)

      # HStack should use intrinsic width (100 + 10 + 150 = 260)
      hstack.bounds.width.should eq(260.0)
      hstack.bounds.height.should eq(60.0)
    end
  end
end

describe "VStack with Expanded" do
  describe "single expanded child" do
    it "expanded child fills remaining height" do
      vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)

      # Fixed child: 100px height
      fixed = TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 100.0))
      vstack.add_child(fixed)

      # Expanded child: should fill remaining 500px
      expanded = CrymbleUI::Expanded.new
      exp_child = TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 50.0))
      expanded.add_child(exp_child)
      vstack.add_child(expanded)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      vstack.layout(constraints, CrymbleUI::Vec2.zero)

      # VStack should use full constraint height
      vstack.bounds.height.should eq(600.0)

      # Fixed child at y=0, height=100
      fixed.bounds.y.should eq(0.0)
      fixed.bounds.height.should eq(100.0)

      # Expanded child at y=100, height=500 (remaining space)
      expanded.bounds.y.should eq(100.0)
      expanded.bounds.height.should eq(500.0)
    end
  end

  describe "multiple expanded children" do
    it "splits remaining height equally between two expanded children" do
      vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)

      # Fixed child: 200px height
      fixed = TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 200.0))
      vstack.add_child(fixed)

      # Two expanded children should each get 200px (400 / 2)
      exp1 = CrymbleUI::Expanded.new
      exp1.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 50.0)))
      vstack.add_child(exp1)

      exp2 = CrymbleUI::Expanded.new
      exp2.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 50.0)))
      vstack.add_child(exp2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      vstack.layout(constraints, CrymbleUI::Vec2.zero)

      # Fixed: y=0, height=200
      fixed.bounds.height.should eq(200.0)

      # exp1: y=200, height=200
      exp1.bounds.y.should eq(200.0)
      exp1.bounds.height.should eq(200.0)

      # exp2: y=400, height=200
      exp2.bounds.y.should eq(400.0)
      exp2.bounds.height.should eq(200.0)
    end
  end

  describe "backward compatibility" do
    it "behaves unchanged when no expanded children (loose constraints)" do
      vstack = CrymbleUI::VStack.new(spacing: 10.0, padding: 0.0)

      child1 = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
      child2 = TestWidget.new(measured_size: CrymbleUI::Size.new(150.0, 60.0))
      vstack.add_child(child1)
      vstack.add_child(child2)

      # Use loose constraints (like original tests) - VStack uses intrinsic size
      constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800.0, 600.0))
      vstack.layout(constraints, CrymbleUI::Vec2.zero)

      # VStack should use intrinsic height (50 + 10 + 60 = 120)
      vstack.bounds.height.should eq(120.0)
      vstack.bounds.width.should eq(150.0)
    end
  end
end

describe "expanded DSL helper" do
  it "creates Expanded widget with child" do
    # Create a simple test widget that includes the DSL
    hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

    # Manually create what DSL would do
    exp = CrymbleUI::Expanded.new
    child = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
    exp.add_child(child)
    hstack.add_child(exp)

    # Verify structure
    hstack.children.size.should eq(1)
    hstack.children.first.should be_a(CrymbleUI::Expanded)
    hstack.children.first.children.size.should eq(1)
  end
end

# NEW TESTS: Child bounds and cross-axis behavior
describe "child bounds match expanded bounds" do
  it "HStack: child fills expanded's allocated width" do
    hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

    fixed = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
    hstack.add_child(fixed)

    expanded = CrymbleUI::Expanded.new
    exp_child = TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 30.0))
    expanded.add_child(exp_child)
    hstack.add_child(expanded)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    hstack.layout(constraints, CrymbleUI::Vec2.zero)

    # Expanded should be 700px wide (800 - 100)
    expanded.bounds.width.should eq(700.0)

    # CRITICAL: Child should ALSO be 700px wide (fills Expanded)
    exp_child.bounds.width.should eq(700.0)
  end

  it "VStack: child fills expanded's allocated height" do
    vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)

    fixed = TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 100.0))
    vstack.add_child(fixed)

    expanded = CrymbleUI::Expanded.new
    exp_child = TestWidget.new(measured_size: CrymbleUI::Size.new(150.0, 50.0))
    expanded.add_child(exp_child)
    vstack.add_child(expanded)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    vstack.layout(constraints, CrymbleUI::Vec2.zero)

    # Expanded should be 500px tall (600 - 100)
    expanded.bounds.height.should eq(500.0)

    # CRITICAL: Child should ALSO be 500px tall (fills Expanded)
    exp_child.bounds.height.should eq(500.0)
  end
end

describe "nested containers respect tight constraints" do
  it "HStack inside Expanded fills the allocated space" do
    vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)

    # Expanded containing an HStack (no Expanded children inside)
    expanded = CrymbleUI::Expanded.new
    inner_hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)
    inner_hstack.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 30.0)))
    expanded.add_child(inner_hstack)
    vstack.add_child(expanded)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    vstack.layout(constraints, CrymbleUI::Vec2.zero)

    # Expanded should fill full height (600)
    expanded.bounds.height.should eq(600.0)

    # CRITICAL: inner_hstack must ALSO fill height because it receives tight constraints
    inner_hstack.bounds.height.should eq(600.0)
  end

  it "VStack inside Expanded fills the allocated space" do
    hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

    # Expanded containing a VStack (no Expanded children inside)
    expanded = CrymbleUI::Expanded.new
    inner_vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    inner_vstack.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 30.0)))
    expanded.add_child(inner_vstack)
    hstack.add_child(expanded)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    hstack.layout(constraints, CrymbleUI::Vec2.zero)

    # Expanded should fill full width (800)
    expanded.bounds.width.should eq(800.0)

    # CRITICAL: inner_vstack must ALSO fill width because it receives tight constraints
    inner_vstack.bounds.width.should eq(800.0)
  end
end

describe "demo structure nesting" do
  it "VStack > Expanded(fill_area) > VStack > HStack > Expanded > HStack fills width" do
    # Matches exact demo structure for page 1
    # main_expanded uses fill_area: true to fill both axes (container use case)
    root_vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    main_expanded = CrymbleUI::Expanded.new(fill_area: true)  # Fill both axes!
    demo_vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    outer_hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)
    inner_expanded = CrymbleUI::Expanded.new  # Default: fill main axis only
    inner_hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

    inner_hstack.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 30.0)))
    inner_expanded.add_child(inner_hstack)
    outer_hstack.add_child(inner_expanded)
    demo_vstack.add_child(outer_hstack)
    main_expanded.add_child(demo_vstack)
    root_vstack.add_child(main_expanded)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    root_vstack.layout(constraints, CrymbleUI::Vec2.zero)

    # main_expanded should fill full width (800) because fill: true
    main_expanded.bounds.width.should eq(800.0)
    # inner_hstack should also fill full width
    inner_hstack.bounds.width.should eq(800.0)
  end

  it "Expanded without fill uses natural cross-axis size" do
    # Page 3 scenario: inner Expanded should NOT stretch horizontally
    root_vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    expanded = CrymbleUI::Expanded.new  # No fill parameter = natural cross-axis
    inner_vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    inner_vstack.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(150.0, 30.0)))
    expanded.add_child(inner_vstack)
    root_vstack.add_child(expanded)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    root_vstack.layout(constraints, CrymbleUI::Vec2.zero)

    # Height should fill (main axis of VStack) - 600
    expanded.bounds.height.should eq(600.0)
    # Width should be natural (150), NOT 800
    expanded.bounds.width.should eq(150.0)
  end
end

describe "HStack/VStack respect tight constraints" do
  it "HStack respects tight width constraints (no Expanded children)" do
    outer_hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)
    expanded = CrymbleUI::Expanded.new
    inner_hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)
    inner_hstack.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 30.0)))
    expanded.add_child(inner_hstack)
    outer_hstack.add_child(expanded)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    outer_hstack.layout(constraints, CrymbleUI::Vec2.zero)

    # inner_hstack should fill Expanded's width (800), not intrinsic (100)
    inner_hstack.bounds.width.should eq(800.0)
  end

  it "VStack respects tight height constraints (no Expanded children)" do
    outer_vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    expanded = CrymbleUI::Expanded.new
    inner_vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    inner_vstack.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 30.0)))
    expanded.add_child(inner_vstack)
    outer_vstack.add_child(expanded)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    outer_vstack.layout(constraints, CrymbleUI::Vec2.zero)

    # inner_vstack should fill Expanded's height (600), not intrinsic (30)
    inner_vstack.bounds.height.should eq(600.0)
  end
end

describe "Expanded fills main axis, natural cross axis" do
  it "HStack: expanded fills width (main), uses natural height (cross)" do
    hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

    expanded = CrymbleUI::Expanded.new
    exp_child = TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 30.0))
    expanded.add_child(exp_child)
    hstack.add_child(expanded)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    hstack.layout(constraints, CrymbleUI::Vec2.zero)

    # Width should fill (800) - main axis (tight from HStack)
    expanded.bounds.width.should eq(800.0)

    # Height should be NATURAL (30) - cross axis (loose from HStack)
    expanded.bounds.height.should eq(30.0)
  end

  it "VStack: expanded fills height (main), uses natural width (cross)" do
    vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)

    expanded = CrymbleUI::Expanded.new
    exp_child = TestWidget.new(measured_size: CrymbleUI::Size.new(150.0, 50.0))
    expanded.add_child(exp_child)
    vstack.add_child(expanded)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
    vstack.layout(constraints, CrymbleUI::Vec2.zero)

    # Height should fill (600) - main axis (tight from VStack)
    expanded.bounds.height.should eq(600.0)

    # Width should be NATURAL (150) - cross axis (loose from VStack)
    expanded.bounds.width.should eq(150.0)
  end
end

# FLEX FACTOR TESTS
describe "flex factors" do
  describe "HStack with flex factors" do
    it "distributes space proportionally (flex 1:2)" do
      hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

      # Fixed child: 200px
      fixed = TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 50.0))
      hstack.add_child(fixed)

      # Remaining space: 600px
      # flex:1 should get 200px (1/3 of 600)
      # flex:2 should get 400px (2/3 of 600)
      exp1 = CrymbleUI::Expanded.new(flex: 1)
      exp1.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0)))
      hstack.add_child(exp1)

      exp2 = CrymbleUI::Expanded.new(flex: 2)
      exp2.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0)))
      hstack.add_child(exp2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      hstack.layout(constraints, CrymbleUI::Vec2.zero)

      # Fixed: x=0, width=200
      fixed.bounds.width.should eq(200.0)

      # exp1 (flex:1): x=200, width=200 (1/3 of 600)
      exp1.bounds.x.should eq(200.0)
      exp1.bounds.width.should eq(200.0)

      # exp2 (flex:2): x=400, width=400 (2/3 of 600)
      exp2.bounds.x.should eq(400.0)
      exp2.bounds.width.should eq(400.0)
    end

    it "distributes space proportionally (flex 1:1:2)" do
      hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

      # 400px remaining space, 4 total flex
      exp1 = CrymbleUI::Expanded.new(flex: 1)  # 100px
      exp1.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0)))
      hstack.add_child(exp1)

      exp2 = CrymbleUI::Expanded.new(flex: 1)  # 100px
      exp2.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0)))
      hstack.add_child(exp2)

      exp3 = CrymbleUI::Expanded.new(flex: 2)  # 200px
      exp3.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0)))
      hstack.add_child(exp3)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 100.0))
      hstack.layout(constraints, CrymbleUI::Vec2.zero)

      exp1.bounds.width.should eq(100.0)
      exp2.bounds.width.should eq(100.0)
      exp3.bounds.width.should eq(200.0)
    end
  end

  describe "VStack with flex factors" do
    it "distributes space proportionally (flex 1:2)" do
      vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)

      # Fixed child: 100px
      fixed = TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 100.0))
      vstack.add_child(fixed)

      # Remaining space: 500px
      # flex:1 should get ~166.67px (1/3 of 500)
      # flex:2 should get ~333.33px (2/3 of 500)
      exp1 = CrymbleUI::Expanded.new(flex: 1)
      exp1.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 50.0)))
      vstack.add_child(exp1)

      exp2 = CrymbleUI::Expanded.new(flex: 2)
      exp2.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(200.0, 50.0)))
      vstack.add_child(exp2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      vstack.layout(constraints, CrymbleUI::Vec2.zero)

      # Fixed: y=0, height=100
      fixed.bounds.height.should eq(100.0)

      # exp1 (flex:1): y=100, height ~166.67
      exp1.bounds.y.should eq(100.0)
      exp1.bounds.height.should be_close(166.67, 0.01)

      # exp2 (flex:2): y ~266.67, height ~333.33
      exp2.bounds.y.should be_close(266.67, 0.01)
      exp2.bounds.height.should be_close(333.33, 0.01)
    end
  end

  describe "flex default value" do
    it "defaults flex to 1" do
      hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

      # Two expanded without explicit flex = both flex:1 = equal split
      exp1 = CrymbleUI::Expanded.new  # flex defaults to 1
      exp1.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0)))
      hstack.add_child(exp1)

      exp2 = CrymbleUI::Expanded.new(flex: 1)  # explicit flex:1
      exp2.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0)))
      hstack.add_child(exp2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 100.0))
      hstack.layout(constraints, CrymbleUI::Vec2.zero)

      # Both should get equal width (200 each)
      exp1.bounds.width.should eq(200.0)
      exp2.bounds.width.should eq(200.0)
    end
  end

  describe "flex with spacing" do
    it "accounts for spacing when distributing proportionally" do
      hstack = CrymbleUI::HStack.new(spacing: 10.0, padding: 0.0)

      # 400px - 10px spacing = 390px remaining for 3 flex
      exp1 = CrymbleUI::Expanded.new(flex: 1)  # 130px
      exp1.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0)))
      hstack.add_child(exp1)

      exp2 = CrymbleUI::Expanded.new(flex: 2)  # 260px
      exp2.add_child(TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0)))
      hstack.add_child(exp2)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 100.0))
      hstack.layout(constraints, CrymbleUI::Vec2.zero)

      exp1.bounds.width.should eq(130.0)
      exp2.bounds.width.should eq(260.0)
    end
  end
end

# SPACER TESTS
describe "spacer DSL" do
  it "creates empty expanded that takes remaining space" do
    # This tests the DSL - spacer should create an empty Expanded
    hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

    # Fixed left
    left = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
    hstack.add_child(left)

    # Spacer (DSL creates empty Expanded)
    spacer = CrymbleUI::Expanded.new  # This is what spacer() should create
    hstack.add_child(spacer)

    # Fixed right
    right = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
    hstack.add_child(right)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 100.0))
    hstack.layout(constraints, CrymbleUI::Vec2.zero)

    # Spacer should take remaining 200px
    spacer.bounds.width.should eq(200.0)
    # Right should be pushed to x=300
    right.bounds.x.should eq(300.0)
  end

  it "spacer supports flex factor" do
    hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

    # Two spacers with different flex
    spacer1 = CrymbleUI::Expanded.new(flex: 1)  # spacer(flex: 1)
    hstack.add_child(spacer1)

    spacer2 = CrymbleUI::Expanded.new(flex: 2)  # spacer(flex: 2)
    hstack.add_child(spacer2)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 100.0))
    hstack.layout(constraints, CrymbleUI::Vec2.zero)

    # spacer1 (flex:1): 100px
    spacer1.bounds.width.should eq(100.0)
    # spacer2 (flex:2): 200px
    spacer2.bounds.width.should eq(200.0)
  end
end

# FLEXIBLE (FIT: LOOSE) TESTS
describe "fit: :loose (flexible behavior)" do
  it "allocates space but child uses natural size" do
    hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

    # Child with 100px natural width in 300px allocated space
    flexible = CrymbleUI::Expanded.new(fit: :loose)
    child = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
    flexible.add_child(child)
    hstack.add_child(flexible)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 100.0))
    hstack.layout(constraints, CrymbleUI::Vec2.zero)

    # Flexible (container) takes full 300px
    flexible.bounds.width.should eq(300.0)
    # Child uses natural size (100px), NOT 300px
    child.bounds.width.should eq(100.0)
  end

  it "positions child at start of allocated space" do
    hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

    flexible = CrymbleUI::Expanded.new(fit: :loose)
    child = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
    flexible.add_child(child)
    hstack.add_child(flexible)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 100.0))
    hstack.layout(constraints, CrymbleUI::Vec2.zero)

    # Child at x=0 within flexible's bounds
    child.bounds.x.should eq(0.0)
  end

  it "fit: :tight (default) forces child to fill" do
    hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

    # Default fit is :tight
    expanded = CrymbleUI::Expanded.new  # fit: :tight by default
    child = TestWidget.new(measured_size: CrymbleUI::Size.new(100.0, 50.0))
    expanded.add_child(child)
    hstack.add_child(expanded)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 100.0))
    hstack.layout(constraints, CrymbleUI::Vec2.zero)

    # Child is forced to 300px (fills Expanded)
    child.bounds.width.should eq(300.0)
  end

  it "flexible works with flex factors" do
    hstack = CrymbleUI::HStack.new(spacing: 0.0, padding: 0.0)

    # flex:1 with fit:loose
    flex1 = CrymbleUI::Expanded.new(flex: 1, fit: :loose)
    child1 = TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0))
    flex1.add_child(child1)
    hstack.add_child(flex1)

    # flex:2 with fit:tight (default)
    flex2 = CrymbleUI::Expanded.new(flex: 2)
    child2 = TestWidget.new(measured_size: CrymbleUI::Size.new(50.0, 50.0))
    flex2.add_child(child2)
    hstack.add_child(flex2)

    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 100.0))
    hstack.layout(constraints, CrymbleUI::Vec2.zero)

    # flex1: allocated 100px, child uses natural 50px
    flex1.bounds.width.should eq(100.0)
    child1.bounds.width.should eq(50.0)

    # flex2: allocated 200px, child fills 200px
    flex2.bounds.width.should eq(200.0)
    child2.bounds.width.should eq(200.0)
  end
end
