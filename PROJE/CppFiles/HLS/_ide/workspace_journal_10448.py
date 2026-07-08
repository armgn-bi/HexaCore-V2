# 2025-12-15T19:57:52.155662700
import vitis

client = vitis.create_client()
client.set_workspace(path="HLS")

vitis.dispose()

