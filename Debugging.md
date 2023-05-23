# Debugging

## `Error: UPGRADE FAILED: cannot patch "onms-post-config" with kind Job`

If you get the message above with a huge long error message, it's because you are trying to upgrade a Helm release that still has the onms-post-config job around.
Either the job never started (if the release is still coming up, or there was a problem leaving the release stuck), it is running, or it finished but hasn't been purged yet.
You can delete the job with `kubectl delete job onms-post-config -n <namespace>` (make sure to substitute in the right namespace) and re-run the helm upgrade and you should be fine.
The default timeout is 300 seconds but it can be tweaked by setting `opennms.postConfigJob.ttlSecondsAfterFinished.
For testing, you can also add the `kill-it-with-fire.yaml` values file when you run Helm to significantly reduce the time the job is left around after completing (note that it tweaks other things, too, see the comments in this file).
