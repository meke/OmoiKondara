CFLAGS = -I/usr/include/rpm
LDFLAGS = -lrpm -lpopt -lrpmio -lrpmdb

TARGET = rpmvercmp

all: $(TARGET)

clean:
	$(RM) -f $(TARGET) $(TARGET).o
	$(RM) -f *~
