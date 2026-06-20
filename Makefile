# CrymbleUI Build Targets
# Usage: make [examples|tutorials|all]

EXAMPLES = hello_world stress_test panels_demo stress_panel_demo statusbar_demo \
           checkbox_demo expanded_demo menubar_demo overlay_demo text_input_demo \
           recursive_grid_demo drag_drop_demo scroll_view_demo combo_box_demo \
           multi_combo_box_demo showcase_demo virtual_matrix_demo

TUTORIALS = tutorial-01 tutorial-02 tutorial-03 tutorial-04 tutorial-05 \
            tutorial-06 tutorial-07 tutorial-08 tutorial-09 tutorial-10 \
            tutorial-11 tutorial-12 tutorial-13 tutorial-14 tutorial-15 \
            tutorial-16 tutorial-17 tutorial-18 tutorial-19 tutorial-20 \
            tutorial-21 tutorial-22 tutorial-23 tutorial-24 tutorial-25 \
            tutorial-26 tutorial-27

.PHONY: all examples tutorials clean

all: examples tutorials

examples:
	shards build $(EXAMPLES)

tutorials:
	shards build $(TUTORIALS)

clean:
	rm -rf bin/*
