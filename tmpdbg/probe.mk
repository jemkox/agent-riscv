probe:
	@setsid bash -c "sleep 30; touch /home/jemko/agent-workspace/hdl/rv32cpu/tmpdbg/survives.flag" &
	@echo launched
