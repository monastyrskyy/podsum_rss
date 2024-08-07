# podsum_rss
Parsing RSS file(s) to transcribe podcasts.

1. The goal is to have a DEV, INT, and PROD env on Azure; same subscription, but different resource groups.

8/7/24 For the past three days, the Python FUnction App on Azure has been having issues.
sometimes it creates the app, and deletes it later; sometimes it doesn't create it. sometimes the app works for a bit but then can't be found.
sometimes refreshing the function app duplicates the apps that are there, and azure doesn't care that they're named the same way.
then it cares all of a sudden.


I have already got this function to work with PowerShell Core. I might be going forward with this, although I'd like to have it be with Python.

The issue Azure says is with the runtime env, which is Linux. It also says it's been having long term issues with it. over the past three days, it has not been working consistently and has been very frustrating.

