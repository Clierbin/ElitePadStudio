#include <iostream>
#include <sstream>
/*
 * xow-mac - Xbox Wireless Adapter driver for macOS
 * Copyright (C) 2026
 *
 * Based on xow, Copyright (C) 2019 Medusalix
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

#include "utils/log.h"
#include "dongle/usb.h"
#include "dongle/dongle.h"

#include <cstring>
#include <csignal>
#include <unistd.h>

int main()
{
    Log::init();
    Log::info("xow-mac %s (based on xow by Severin v. W.)", VERSION);

    sigset_t signalMask;

    sigemptyset(&signalMask);
    sigaddset(&signalMask, SIGINT);
    sigaddset(&signalMask, SIGTERM);
    sigaddset(&signalMask, SIGUSR1);

    // Block signals in all threads; the main thread collects them via
    // sigwait (macOS has no signalfd)
    if (pthread_sigmask(SIG_BLOCK, &signalMask, nullptr))
    {
        Log::error("Error blocking signals: %s", strerror(errno));

        return EXIT_FAILURE;
    }

    UsbDeviceManager manager;

    // USB errors terminate the daemon by signaling the main thread
    UsbDevice::Terminate terminate = []
    {
        kill(getpid(), SIGTERM);
    };
    std::unique_ptr<UsbDevice> device = manager.getDevice({
        { DONGLE_VID, DONGLE_PID_OLD },
        { DONGLE_VID, DONGLE_PID_NEW },
        { DONGLE_VID, DONGLE_PID_SURFACE }
    }, terminate);

    Dongle dongle(std::move(device));

    std::string line;
    while (std::getline(std::cin,line)) {
        if(line=="LIST"){auto v=dongle.listProfilePads(); for(char& c:v)if(c=='\n')c=';';std::cout<<"OK "<<v<<std::endl;continue;}
        if(line=="PAIR"){std::cout<<(dongle.setPairingStatus(true)?"OK":"ERR")<<std::endl;continue;}
        if(line.rfind("LIVE ",0)==0 || line.rfind("PULSE ",0)==0){std::istringstream m(line);std::string op,mac,gen;int motor=-1;m>>op>>mac>>gen;if(op=="PULSE" && (!(m>>motor)||motor<0||motor>3)){std::cout<<"ERR motor"<<std::endl;continue;}std::cout<<dongle.monitor(mac+" "+gen,motor)<<std::endl;continue;}
        if(line=="QUIT") break;
        std::istringstream in(line);std::string mac,gen,hex;in>>mac>>gen>>hex; Bytes frame,reply;
        if(hex.size()%2 || hex.size()<10 || hex.size()>128 || hex.find_first_not_of("0123456789abcdef")!=std::string::npos){std::cout<<"ERR invalid"<<std::endl;continue;}
        for(size_t i=0;i<hex.size();i+=2)frame.append(uint8_t(std::stoi(hex.substr(i,2),nullptr,16)));
        auto err=dongle.exchangeProfile(mac+" "+gen,frame,reply);
        if(err.empty())std::cout<<"OK "<<Log::formatBytes(reply)<<std::endl;else std::cout<<"ERR "<<err<<std::endl;
    }
    return 0;
}
