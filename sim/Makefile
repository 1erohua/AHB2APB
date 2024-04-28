export TEST_NAME = AHB_TO_APB
FILE_LIST = $(TEST_NAME).f

PLATFORM = LINUX64
waveform = $(TEST_NAME).fsdb

all:clean vcs_make

#-R是编译完成之后立即运行
#-full64  支持64位运行
#+v2k 支持verilog 2001特性
#-fsdb 调用verdi PLI库，支持fsdb波形
#+define+<macro_name>=<value> 命令行进行宏定义，在代码中使用了`ifdef 编译指令
#-sverilog 支持system verilog语法
#-l 生成指定的log文件
#-f 指定文件列表的文件名，文件中可包括源代码文件的路径和名称，也可以包括编译选项参数

vcs_make:
	vcs -R -full64 +v2k -fsdb +define+FSDB -sverilog -f $(FILE_LIST)  -l run.log -timescale=1ns/1ps

run_verdi:
	verdi -nologo -sv -f $(FILE_LIST) -ssf $(waveform) &

clean:
	rm -rf *fsdb*  *csrc* DVEfiles simv simv.daidir ucli.key novas* VCS* *dat xvlog* *.log ./../rtl/xvlog* ./../tb/xvlog*  xsim.dir ./../rtl/xsim.dir ./../tb/xsim.dir


