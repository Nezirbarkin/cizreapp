# -*- coding: utf-8 -*-
import subprocess

# All dangling blobs
blobs = [
    '06c01f80c7dbab3952577450e2d8c7ad3ef2e42a',
    '3c20724067222fdb44c5f55761a4347e02c1f14f',
    '3fc17150adf6bb4d2a2a872845d0dcf487875f35',
    '9541a6ba1ff31b4c8f3fc200ab221d6518c79056',
    'a3c1ea1620c2677a07fc9e253054a7657c6750e5',
    'c1412017124575ac19d8dcf54ee744d4b2d8b3cf',
    'f0412e4b9b2196970e83a2883fd70ddb84d5281e',
    '2222681466dcca92028ab7578af64d2d5b65f9cb',
    '5d821114ea8c3e6ca61ad244371a929eafb55828',
    'acc3e09a62cb9d75865fd09820fe950470e87340',
    '8d84232167c495ff6b4427b2a1e780efde19a6ba',
    '97041f4cc5a968c74ac822d8cbd4fcb00df24d89',
    '9fe4053050a9ac2fcdffb4cddb7654226929ffb8',
    '78a5c6f7611fcf625d9d3385e4e96403e194c9c1',
    'b58529b00a004c9f18a0d0946a6cfdd76c7230da',
    'c925da7c84c8593908f8aa52f2deb12a58c56f0e',
    'dc671cd34fe0c7d1b4dc548d245b76fac57ff3d9',
    '76a81d2d80e06851dd15564d2235568f5b137bea',
    'a8089d41aa81973af442c99533effdad83c8b933',
    'cbe8293da3fc6c1b044c8cecf197dd7c8840c112',
    'eca8ae002b4ac30318f5d29ac87ce5384292923a',
    'a6a90601a260504dba4bcbb40eba739e6f63de85',
    '1af740150d6b40b079f0cbe9bbf1078d6e518854',
    '2f573e6fcd12244421e2dc42edc4e6c46f48f917',
    '9237966bd6dd70bfb07495a64d82e052f9cd7d5f',
    '2b0f06040730f75fc60893088e2d76761188c9db',
    '5e0f1c621d98d10fca100c5d7894ce0a43999d34',
    'ec30d43c7718700f6a6a8ec14ac619f549bd14df',
    '6b7200e0f4b852e3957525771bd068bad061d82e',
    'c0f2c6e37b531769b8564d7e14eea977d9c12228',
    'a73331564102a528fa7ec1e1c411777d08248e72',
    'fd54e4a96c363b0a828e9ce87e8d2efd01c32134',
    '785582ecea89ce629a066ff7e84608b5f960a3ea',
    'e6958acd631fffbf67fed8b3020cdb2a01611536',
    '39f6cdb039ea1e35f75ece70fdac2192a68d6c2d',
    '27bca1fd010b973b0464b97c86c038af0d128589',
    '4a7ce9dc41c63c07d8f7fda373a284ba68f3a5f9',
    '89dcfc66123ddd64056e10c63dd63a01ab86c5d3',
    '73ddf2be2956d34eea2a151aaa4a76992a134b59',
    'ca7d455b41f5139dbd8209f2d4adfc7362ba3737',
    'c39eafea619efe09b02a6e4138958714535240c8',
    'b63fe8bd169c0af304c8188627c8c3098d8a1498',
]

for blob in blobs:
    result = subprocess.run(['git', 'cat-file', '-p', blob], capture_output=True, cwd=r'c:\Users\lenovo\cizreapp')
    if result.returncode == 0:
        content = result.stdout
        if b'_buildProviderDropdown' in content or b'AIManagementContent' in content:
            size = len(content)
            if size > 50000:  # Our file is ~63KB
                print(f'LIKELY MATCH! Blob: {blob} ({size} bytes)')
                print(f'First 100: {content[:100]}')
                # Save it
                path = r'lib\features\admin\widgets\ai_management_content.dart'
                with open(path, 'wb') as f:
                    f.write(content)
                print(f'SAVED!')
                break
            else:
                print(f'Small match: {blob} ({size} bytes)')
        else:
            pass  # Skip printing for non-matches
    else:
        print(f'{blob}: error')