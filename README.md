# bsab (Binance Spot Assets Balance)
![bsab-demo](https://github.com/mvidaldp/bsab/raw/main/demo.gif)

Display a Binance account spot assets total balance in real-time.

__How to set it up?__

- Create your API key: https://www.binance.com/en-NG/support/faq/360002502072
- Put your secret and API keys into [`keys.json`](https://github.com/mvidaldp/bsab/blob/main/keys.json).

```json
{
    "secret": "yoursecretapikey",
    "key": "yourapikey"
}
```

__How to use?__ In your Linux shell, just run: 
```bash
# -i or --investment with your base investment value (default is 0)
bash bsab.sh -i 1000
# or (if you give it execution permissions, aka chmod +x)
./bsab.sh -i 1000
```
