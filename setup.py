from setuptools import setup, Distribution

# Trick setuptools into thinking this is a binary distribution
# so it generates a platform-specific wheel tag (e.g. cp313-cp313-win_amd64).
class BinaryDistribution(Distribution):
    def has_ext_modules(self):
        return True

setup(distclass=BinaryDistribution)