.PHONY: test

test:
	nvim --headless -u NONE -c "luafile script/run_tests.lua" --
