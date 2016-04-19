from oeqa.oetest import oeRuntimeTest
from oeqa.utils.decorators import tag
import time

class App(object):
    def __init__(self,target):
        self.target = target

    def getProcessInfo(self,keyword):
        ''' get username,pid and exec command of process '''
        (status,output) = self.target.run(" ps axo user:20,pid,comm | grep -v grep | grep %s | head -1" % keyword)
        if status == 0 and output.strip():
             return output
        else:
             return None
        
    def startApp(self,service_name):
        ''' start app '''
        (status,output) = self.target.run("systemctl start %s" % service_name)
        time.sleep(3)
        if status != 0 :
            return False

        if self.getProcessInfo('node')!= None and \
           self.getProcessInfo('systemd-nspawn') != None:
            return True
        else:
            return False 
         
        
    def stopApp(self,service_name):
        ''' stop app '''
        (status,output) = self.target.run("systemctl stop %s" % service_name)
        time.sleep(3)
        if status != 0 :
            print output
            return False
        if self.getProcessInfo('node')== None and \
           self.getProcessInfo('systemd-nspawn') == None :
            return True
        else:
            return False
        
class AppFWTest(oeRuntimeTest):

    node_app_name = 'iodine-nodetest'

    def setUp(self):
        self.app = App(self.target)

    def _getProcessInfo(self,name):
        ''' get username,pid and exec command of process '''
        return self.app.getProcessInfo(name)

    def _startApp(self,name):
        ''' start app '''
        self.assertTrue(self.app.startApp(name),'Fail to start app')
        
    def _stopApp(self,name):
        ''' stop app '''
        self.assertTrue(self.app.stopApp(name),'Fail to stop app')

    @tag(TestType = 'FVT', FeatureID = 'IOTOS-337')
    def test_appFW_install_pkg_during_img_creation(self):
        '''check app is pre-installed'''
        (chk_example_app,output) = self.target.run("ls /apps/iodine/nodetest/")
        self.assertTrue(chk_example_app == 0 ,
                        "example-app is not integreated in image")
        
    @tag(TestType = 'FVT', FeatureID = 'IOTOS-337')
    def test_appFW_app_start(self):
        ''' Check app start successfully '''
        self._startApp(self.node_app_name)

    @tag(TestType = 'FVT', FeatureID = 'IOTOS-337')
    def test_appFW_app_stop(self):
        ''' Check app stop successfully '''
        self._startApp(self.node_app_name)
        self._stopApp(self.node_app_name)

    @tag(TestType = 'EFT', FeatureID = 'IOTOS-337')
    def test_appFW_app_restart(self):
        ''' Check app restart successfully '''
        self._startApp(self.node_app_name)
        self._stopApp(self.node_app_name)
        self._startApp(self.node_app_name)

    @tag(TestType = 'EFT', FeatureID = 'IOTOS-337')
    def test_appFW_app_restop(self):
        ''' Check app restop successfully '''
        self._startApp(self.node_app_name)
        self._stopApp(self.node_app_name)
        self._startApp(self.node_app_name)
        self._stopApp(self.node_app_name)

    @tag(TestType = 'EFT', FeatureID = 'IOTOS-337')
    def test_appFW_app_restart_systemctl(self):
        ''' Check app restop successfully '''
        self._startApp(self.node_app_name)
        (status,output) = self.target.run("systemctl restart %s" % self.node_app_name)
        time.sleep(5)
        self.assertTrue(status == 0 , 'App restart by systemctl fail')
        self.assertTrue(self._getProcessInfo('node')== None and 
                        self._getProcessInfo('systemd-nspawn') == None,'App restart by systemctl fail')
    
    @tag(TestType = 'FVT', FeatureID = 'IOTOS-339')
    def test_appFW_app_running_with_Dedicated_User(self):
        ''' check app launched by normal user '''
        self._startApp(self.node_app_name)
        p_name = self._getProcessInfo(self.node_app_name).split()[0]
        self.assertTrue(self.node_app_name == p_name , "Not found app running with dedicated user")

    @tag(TestType = 'FVT', FeatureID = 'IOTOS-342')
    def test_appFW_app_container_list(self):
        ''' check app listed in container '''
        self._startApp(self.node_app_name)
        (status,output) = self.target.run("machinectl -l")
        self.assertTrue(status == 0 and self.node_app_name in output , '%s : app not running in container' % output) 

    @tag(TestType = 'FVT', FeatureID = 'IOTOS-342')
    def test_appFW_app_container_status(self):
        ''' check app status in container '''
        self._startApp(self.node_app_name)
        (status,output) = self.target.run("machinectl status %s" % self.node_app_name)
        self.assertTrue(status == 0 and self.node_app_name in output , '%s : app not running in container' % output) 
        (status,output) = self.target.run("machinectl show %s" % self.node_app_name)
        self.assertTrue(status == 0 and 'State=running' in output , '%s : app not running in container' % output) 
         
    @tag(TestType = 'FVT', FeatureID = 'IOTOS-416')
    def test_appFW_app_impersonation(self):
        ''' check access of app user accout '''
        self.test_appFW_install_pkg_during_img_creation()
        (status,output) = self.target.run("su %s" % self.node_app_name)
        self.assertTrue(status != 0 , 'Test access of app user fail')
         
    @tag(TestType = 'FVT', FeatureID = 'IOTOS-358')
    def test_appFW_sqlite_integrated(self):
        ''' Check sqlite is integrated in image'''
        (status,output) = self.target.run("ls /usr/lib/libsqlite*.so || ls /lib/libsqlite*.so")
        self.assertTrue(status == 0 , 'Check sqlite integration fail')
       
