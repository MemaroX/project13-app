import asyncio
from telegram import Bot

 
TOKEN = '8603083667:AAFaHCubBGTA3f93KKcovmErNK8kqI4nWJ4'

# Corrected dictionary name and content
messages = {
    "DEM": "🚨 تنبيه طبي: المريض في حالة نوبة سكر يحتاج للمساعدة فورًا!",
    "POC": "🚨 تنبيه أمني: هناك اختراق أمني للشقة!"
}

# Recipient IDs
CHAT_ID_HOSPITAL    = '1509520169' #MA
CHAT_ID_POLICE      = '5513195304' #MM

async def send_emergency_messages():
    bot = Bot(token=TOKEN)
    
    async with bot:
        # 1. Send Medical Alert to Hospital
        await bot.send_message(chat_id=CHAT_ID_HOSPITAL, text=messages["DEM"])
        print("تم إرسال بلاغ المستشفى بنجاح")

        # 2. Send Security Alert to Police
        await bot.send_message(chat_id=CHAT_ID_POLICE, text=messages["POC"])
        print("تم إرسال بلاغ الشرطة بنجاح")

if __name__ == '__main__':
    try:
        asyncio.run(send_emergency_messages())
    except Exception as e:
        print(f"حدث خطأ أثناء الإرسال: {e}")
