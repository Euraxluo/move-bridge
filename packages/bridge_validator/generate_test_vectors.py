from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ed25519

# 生成密钥对
private_key = ed25519.Ed25519PrivateKey.generate()
public_key = private_key.public_key()

# 获取公钥字节
public_key_bytes = public_key.public_bytes(
    encoding=serialization.Encoding.Raw,
    format=serialization.PublicFormat.Raw
)

# 测试消息
message = b"Test message"

# 生成签名
signature = private_key.sign(message)

# 打印测试向量
print("Public key (32 bytes):")
print([b for b in public_key_bytes])
print("\nMessage:")
print([b for b in message])
print("\nSignature (64 bytes):")
print([b for b in signature]) 