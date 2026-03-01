.PHONY: test bench

test:
	nvim --headless -u NONE -c "luafile script/run_tests.lua" --

bench:
	nvim --headless -u NONE -c "luafile script/run_bench.lua" --
