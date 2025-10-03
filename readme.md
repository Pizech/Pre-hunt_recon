# Pre-hunt recon
In this repo I will share my periodically udated way of reconnoitering on my target.


<hr>

After choosing a subdomain, I run 4 steps synchronously:
### 1. [Nmap](https://nmap.org/)
Commands diverse deponds on the configuration of the target, but I may use intitally some thing like
```nmap -T4 -A -p- -v target```<br>
I use zenmap btw (no offence please)
### 2. urlCollector
The script urlCollector.bh that I made, collects urls from different techniques. It takes two parameters; first is the target, second is the wordlist (I recommend using small wordlist at first like common.txt in the dirb folder).
Then it validates it and run the scan.<br>
The first scaning technique is [Katana](https://github.com/projectdiscovery/katana) tool, it runs the target, follow urls, and get the data found.<br>
The second one is [Gobuster](https://www.kali.org/tools/gobuster) tool, I prefer using it with katana to get higher portion of urls.<br>
Finally [gau](https://github.com/lc/gau), used to look for urls in expired snapshots of the target from many sources.<br>
The script has 9 output files:
1.KATANA_URLS<br>
2.GOB_RAW<br>
3.GOB_URLS<br>
4.GAU_RAW<br>
5.GAU_URLS<br>
6.COMBINED<br>
7.JS_ONLY<br>
8.GOB_ONLY<br>
9.GAU_ONLY<br>
Check the code to know what they contain and to understand how does it work.<br>

### 3. [Gitdorker]() and [Githound]()
