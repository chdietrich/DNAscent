CC = gcc
CXX = g++
DEBUG = -g
LIBFLAGS = -lrt 
LDFLAGS ?= -ldl -llzma -lbz2 -lm -lz
CXXFLAGS = -Wall -O2 -fopenmp -std=c++14
CFLAGS = -Wall -std=c99 -O2

SPACE:= ;
SPACE+=;
null :=
space := ${null} ${null}
${space} := ${space}

CURRENT_PATH := $(subst $(lastword $(notdir $(MAKEFILE_LIST))),,$(subst $(SPACE),\$(SPACE),$(shell realpath '$(strip $(MAKEFILE_LIST))')))
PATH_SPACEFIX := $(subst ${space},\${space},${CURRENT_PATH})

ifeq ($(zstd),1)
	LDFLAGS += -lzstd
endif

#hdf5
H5_LIB = ./hdf5-1.8.14/hdf5/lib/libhdf5.a
H5_INCLUDE = -I./hdf5-1.8.14/hdf5/include

#hts
HTS_LIB = ./htslib/libhts.a
HTS_INCLUDE = -I./htslib

#tensorflow
TENS_DEPEND = tensorflow/include/tensorflow/c/c_api.h
TENS_LIB = -Wl,-rpath,${PATH_SPACEFIX}tensorflow/lib -L tensorflow/lib -ltensorflow
TENS_INCLUDE = -I./tensorflow/include

#fast5
FAST5_INCLUDE = -I./fast5/include

#pod5
POD5_DEPEND = pod5-file-format/build/Release/lib/libpod5_format.a
POD5_INCLUDE = -I./pod5-file-format/build/c++
POD5_LIB = -L${PATH_SPACEFIX}pod5-file-format/build/Release/lib -lpod5_format 
POD5_LIB += -L${PATH_SPACEFIX}pod5-file-format/build/third_party/libs -larrow -ljemalloc_pic -lzstd

#add include flags for each library
CPPFLAGS += $(H5_INCLUDE) $(HTS_INCLUDE) $(FAST5_INCLUDE) $(TENS_INCLUDE) $(POD5_INCLUDE)

DNASCENT_EXECUTABLE = bin/DNAscent

all: depend $(DNASCENT_EXECUTABLE)

#all each library if they're not already built
htslib/libhts.a:
	cd htslib; \
	make || exit 255; \
	cd ..;

hdf5-1.8.14/hdf5/lib/libhdf5.a:
	if [ ! -e hdf5-1.8.14/hdf5/lib/libhdf5.a ]; then \
		wget https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.8/hdf5-1.8.14/src/hdf5-1.8.14.tar.gz; \
		tar -xzf hdf5-1.8.14.tar.gz || exit 255; \
		cd hdf5-1.8.14 && \
			./configure --enable-threadsafe && \
			make && make install; \
	fi 

tensorflow/include/tensorflow/c/c_api.h:
	if [ ! -e tensorflow/include/tensorflow/c/c_api.h ]; then \
		mkdir tensorflow; \
		cd tensorflow; \
		wget https://storage.googleapis.com/tensorflow/libtensorflow/libtensorflow-gpu-linux-x86_64-2.12.1.tar.gz; \
		tar -xzf libtensorflow-gpu-linux-x86_64-2.12.1.tar.gz || exit 255; \
		cd ..; \
	fi
	
pod5-file-format/build/Release/lib/libpod5_format.a:
	if [ ! -e pod5-file-format/build/Release/lib/libpod5_format.a ]; then \
		pip3 install "conan<2" build; \
		conan --version; \
		cd pod5-file-format; \
		git submodule update --init --recursive; \
		pip3 install setuptools_scm==7.1.0; \
		python3 -m setuptools_scm; \
		python3 -m pod5_make_version; \
		mkdir build; \
		cd build; \
		conan install --build=missing -s build_type=Release .. && cmake -DENABLE_CONAN=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=conan_toolchain.cmake .. && make -j; \
		cd ../..; \
	fi
	
SUBDIRS = src src/scrappie src/pfasta src/sgsmooth
CPP_SRC := $(foreach dir, $(SUBDIRS), $(wildcard $(dir)/*.cpp))
C_SRC := $(foreach dir, $(SUBDIRS), $(wildcard $(dir)/*.c))
DNA_EXE_SRC = src/main/DNAscent.cpp

#log the commit 
src/gitcommit.h: .git/HEAD .git/index
	echo "const char *gitcommit = \"$(shell git rev-parse HEAD)\";" > $@

#log the software path
src/softwarepath.h: 
	echo "const char *executablePath = \"${PATH_SPACEFIX}\";" > $@

#generate object names
CPP_OBJ = $(CPP_SRC:.cpp=.o)
C_OBJ = $(C_SRC:.c=.o)

DNASCENT_OBJ = $(DNA_EXE_SRC:..cpp=.0)

depend: .depend

.depend: $(CPP_SRC) $(C_SRC) $(H5_LIB) $(TENS_DEPEND) $(POD5_DEPEND) src/gitcommit.h src/softwarepath.h
	rm -f ./.depend
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -MM $(CPP_SRC) $(C_SRC) > ./.depend;

#compile each object
.cpp.o: src/gitcommit.h src/softwarepath.h
	$(CXX) -o $@ -c $(CXXFLAGS) $(CPPFLAGS) -fPIC $<

.c.o:
	$(CC) -o $@ -c $(CFLAGS) $(CPPFLAGS) $(H5_INCLUDE) -fPIC $<
	
src/main/DNAscent.o: src/gitcommit.h src/softwarepath.h
	$(CXX) -o $@ -c $(CXXFLAGS) $(CPPFLAGS) -fPIC $<

#compile the main executables
$(DNASCENT_EXECUTABLE): src/main/DNAscent.o $(CPP_OBJ) $(C_OBJ) $(HTS_LIB) $(H5_LIB) $(TENS_DEPEND) $(POD5_DEPEND) src/gitcommit.h src/softwarepath.h
	$(CXX) -o $@ $(CXXFLAGS) $(CPPFLAGS) -fPIC $(DNASCENT_OBJ) $(CPP_OBJ) $(C_OBJ) $(HTS_LIB) $(H5_LIB) $(TENS_LIB) $(POD5_LIB) $(LIBFLAGS) $(LDFLAGS)

clean:
	rm -f $(DNASCENT_EXECUTABLE) $(CPP_OBJ) $(C_OBJ) src/main/DNAscent.o src/gitcommit.h
