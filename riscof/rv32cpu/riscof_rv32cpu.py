import os
import re
import subprocess
import logging
import sys

from riscof.pluginTemplate import pluginTemplate
import riscof.utils as utils

logger = logging.getLogger()

class rv32cpu(pluginTemplate):
    __model__ = 'rv32cpu'
    __version__ = 'l5-riscof'

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get('config')
        if config is None:
            logger.error('rv32cpu config node missing.')
            raise SystemExit(1)
        self.pluginpath = os.path.abspath(config['pluginpath'])
        self.isa_spec = os.path.abspath(config['ispec'])
        self.platform_spec = os.path.abspath(config['pspec'])
        self.num_jobs = str(config.get('jobs', '1'))
        self.project_root = os.path.abspath(os.path.join(self.pluginpath, '..', '..'))
        self.helper = os.path.join(self.pluginpath, 'run_dut.py')
        if not os.path.exists(self.helper):
            logger.error(f'helper missing: {self.helper}')
            raise SystemExit(1)

    def initialise(self, suite, work_dir, archtest_env):
        self.suite = suite
        self.work_dir = work_dir
        self.archtest_env = archtest_env
        self.env = os.path.join(self.pluginpath, 'env')
        self.compile_base = (
            f'riscv64-unknown-elf-gcc -static -mcmodel=medany '
            f'-fvisibility=hidden -nostdlib -nostartfiles -mabi=ilp32 '
            f'-Wl,-m,elf32lriscv -T {self.env}/link.ld '
            f'-I {self.env} -I {archtest_env}'
        )

    def build(self, isa_yaml, platform_yaml):
        ispec = utils.load_yaml(isa_yaml)['hart0']
        self.xlen = '32'
        if 64 in ispec['supported_xlen']:
            self.xlen = '64'
        if self.xlen == '64':
            logger.error('rv32cpu plugin only supports 32-bit xlen.')
            raise SystemExit(1)
        self.isa_str = ispec.get('ISA', 'RV32IMAH_Zicsr_Zifencei')
        for part in ('C', 'F', 'D', 'Zfh'):
            if re.search(rf'\b{part}\b', self.isa_str):
                logger.error('rv32cpu ISA yaml claims an extension this CPU does not implement.')
                raise SystemExit(1)

    def runTests(self, testList):
        for name in testList:
            entry = testList[name]
            test = entry['test_path']
            test_dir = entry['work_dir']
            isa = self.isa_str.lower()
            elf = os.path.join(test_dir, f'dut_{os.path.basename(test)}.elf')
            sig_file = os.path.join(test_dir, self.name[:-1] + '.signature')
            macros = ''.join(' -D' + str(m) for m in entry.get('macros', []))
            cmd = f'{self.compile_base} -march={isa} -o {elf} {test} {macros}'
            logger.debug(f'compile {cmd}')
            subprocess.run(cmd, shell=True, check=True, cwd=test_dir)
            subprocess.run([sys.executable, self.helper, elf, sig_file],
                           check=True, cwd=self.project_root)
