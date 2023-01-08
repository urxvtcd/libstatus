fmt:
	shfmt -w -i 0 -bn -p git-s git-ss libstatus.sh

check:
	@echo "--- shfmt ---"
	shfmt -d -i 0 -bn -p git-s git-ss libstatus.sh test.sh
	@echo "--- shellcheck ---"
	shellcheck --color --enable all --shell sh git-s git-ss libstatus.sh test.sh
	@echo "--- tests ---"
	./test.sh
