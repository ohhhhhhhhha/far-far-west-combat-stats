#pragma once
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
int WSAAPI ffw_record_startup(WORD version,LPWSADATA data);
int WSAAPI ffw_record_cleanup();
#define WSAStartup ffw_record_startup
#define WSACleanup ffw_record_cleanup
